// @copyright André Trettin

import CoreRPG
import Foundation
import os
import os.log

struct SharePlayCompletedPackage: Sendable {
    let id: UUID
    let sourceParticipantId: UUID
    let byteCount: Int
    /// From the first chunk to the last one; `.zero` for a message that came in one chunk.
    var transferDuration: Duration = .zero
    private let chunkStore: OSAllocatedUnfairLock<[Data]>

    init(id: UUID, sourceParticipantId: UUID, chunks: [Data], byteCount: Int) {
        self.id = id
        self.sourceParticipantId = sourceParticipantId
        self.byteCount = byteCount
        self.chunkStore = OSAllocatedUnfairLock(initialState: chunks)
    }

    /// The chunks as they arrived.
    var chunks: [Data] { chunkStore.withLock { $0 } }

    /// Linear-time assembly. Production invokes this from an `@concurrent`
    /// decode helper so large payloads never concatenate on the main actor.
    nonisolated func reassembledData() -> Data {
        Self.assemble(chunkStore.withLock { $0 }, byteCount: byteCount)
    }

    /// Like `reassembledData()`, and lets go of the chunks: for a package that is decoded once,
    /// the chunks and the assembled bytes (and then the decoded model) would otherwise all be in
    /// memory at the same time. A second call finds nothing left. See
    /// CODE_AUDIT_Game_Shareplay §7.3.
    nonisolated func takeReassembledData() -> Data {
        let taken = chunkStore.withLock { chunks in
            defer { chunks = [] }
            return chunks
        }
        return Self.assemble(taken, byteCount: byteCount)
    }

    private nonisolated static func assemble(_ chunks: [Data], byteCount: Int) -> Data {
        var result = Data()
        result.reserveCapacity(byteCount)
        for chunk in chunks {
            result.append(chunk)
        }
        return result
    }
}

struct SharePlayPackageStreamKey: Hashable, Sendable {
    let sourceParticipantId: UUID
    let packageId: UUID
}

@MainActor
final class SharePlayPackageReceiver {
    typealias Sleep = @Sendable (Duration) async throws -> Void

    init(
        maxIncompleteStreams: Int = 64,
        maxIncompleteStreamsPerSource: Int = 16,
        maxPackagesPerStream: Int = 1_024,
        maxPackageByteCount: Int = SharePlaySingleQueuePackageSender.packageSize,
        maxStreamByteCount: Int = SharePlaySingleQueuePackageSender.maxMessageByteCount,
        maxCumulativeByteCount: Int = SharePlaySingleQueuePackageSender.maxOutstandingBytes,
        maxSourceByteCount: Int? = nil,
        expirationInterval: Duration = .seconds(120),
        now: @escaping @MainActor () -> ContinuousClock.Instant = { ContinuousClock().now },
        sleep: @escaping Sleep = { try await Task.sleep(for: $0) }
    ) {
        self.maxIncompleteStreams = max(1, maxIncompleteStreams)
        self.maxIncompleteStreamsPerSource = max(1, maxIncompleteStreamsPerSource)
        self.maxPackagesPerStream = max(1, maxPackagesPerStream)
        self.maxPackageByteCount = max(1, maxPackageByteCount)
        self.maxStreamByteCount = max(1, maxStreamByteCount)
        self.maxCumulativeByteCount = max(1, maxCumulativeByteCount)
        self.maxSourceByteCount = max(1, maxSourceByteCount ?? max(self.maxStreamByteCount, self.maxCumulativeByteCount / 2))
        self.expirationInterval = expirationInterval > .zero ? expirationInterval : .seconds(1)
        self.now = now
        self.sleep = sleep
    }

    private(set) var receivedPackages: [SharePlayPackageStreamKey: PackageMessageList] = [:]
    private(set) var cumulativeIncompleteByteCount = 0
    private let maxIncompleteStreams: Int
    /// Streams one participant may keep incomplete at once; beyond it that participant's own
    /// oldest stream is evicted, so a flood cannot evict anyone else's transfer.
    /// See CODE_AUDIT_16 §6.4.
    private let maxIncompleteStreamsPerSource: Int
    private let maxPackagesPerStream: Int
    private let maxPackageByteCount: Int
    private let maxStreamByteCount: Int
    private let maxCumulativeByteCount: Int
    /// The incomplete bytes one participant may hold. A source over its quota loses its own
    /// oldest stream or has its chunk refused; it never evicts another participant's transfer.
    /// See CODE_AUDIT_Game_Shareplay §5.14.
    private let maxSourceByteCount: Int
    private let expirationInterval: Duration
    private let now: @MainActor () -> ContinuousClock.Instant
    private let sleep: Sleep
    private var lastReceivedAt: [SharePlayPackageStreamKey: ContinuousClock.Instant] = [:]
    private var firstReceivedAt: [SharePlayPackageStreamKey: ContinuousClock.Instant] = [:]
    private var activityOrder: [SharePlayPackageStreamKey: UInt64] = [:]
    private var nextActivityOrder: UInt64 = 0
    private var expirationTask: Task<Void, Never>?
    private var scheduledExpiration: ContinuousClock.Instant?

    func reset() {
        expirationTask?.cancel()
        expirationTask = nil
        scheduledExpiration = nil
        receivedPackages.removeAll()
        cumulativeIncompleteByteCount = 0
        lastReceivedAt.removeAll()
        firstReceivedAt.removeAll()
        activityOrder.removeAll()
        nextActivityOrder = 0
    }

    func received(
        package: PackageMessage,
        from sourceParticipantId: UUID
    ) -> SharePlayCompletedPackage? {
        let receivedAt = now()
        _ = pruneExpired(at: receivedAt)
        let streamKey = SharePlayPackageStreamKey(
            sourceParticipantId: sourceParticipantId,
            packageId: package.uuid
        )

        guard package.total > 0,
              package.total <= maxPackagesPerStream,
              (1...package.total).contains(package.count),
              let packageData = package.data,
              packageData.count <= maxPackageByteCount,
              packageData.count <= maxStreamByteCount,
              packageData.count <= maxCumulativeByteCount
        else {
            scheduleNextExpiration()
            return nil
        }

        if package.total == 1 {
            removeStream(key: streamKey)
            scheduleNextExpiration()
            return SharePlayCompletedPackage(
                id: package.uuid,
                sourceParticipantId: sourceParticipantId,
                chunks: [packageData],
                byteCount: packageData.count
            )
        }

        let packageList: PackageMessageList
        if let list = receivedPackages[streamKey] {
            guard let additionalByteCount = list.additionalByteCount(for: package) else {
                scheduleNextExpiration()
                return nil
            }
            // Exact retries are safe but are not progress and must not extend a
            // stream's expiry indefinitely.
            guard additionalByteCount > 0 else {
                scheduleNextExpiration()
                return nil
            }
            guard list.receivedByteCount <= maxStreamByteCount - additionalByteCount,
                  makeCumulativeCapacity(
                    for: additionalByteCount,
                    excluding: streamKey,
                    preferringSource: sourceParticipantId
                  ),
                  list.insert(package: package)
            else {
                scheduleNextExpiration()
                return nil
            }
            cumulativeIncompleteByteCount += additionalByteCount
            packageList = list
        } else {
            guard makeStreamCapacity(forSource: sourceParticipantId),
                  makeCumulativeCapacity(for: packageData.count, excluding: nil, preferringSource: sourceParticipantId)
            else {
                scheduleNextExpiration()
                return nil
            }
            packageList = PackageMessageList(initialPackage: package)
            receivedPackages[streamKey] = packageList
            firstReceivedAt[streamKey] = receivedAt
            cumulativeIncompleteByteCount += packageData.count
        }
        recordActivity(for: streamKey, at: receivedAt)

        guard packageList.isComplete else {
            scheduleNextExpiration()
            return nil
        }
        var completedPackage = packageList.completedPackage(
            sourceParticipantId: sourceParticipantId
        )
        if let firstReceivedAt = firstReceivedAt[streamKey] {
            completedPackage.transferDuration = firstReceivedAt.duration(to: receivedAt)
        }
        removeStream(key: streamKey)
        scheduleNextExpiration()
        return completedPackage
    }

    /// Removes package streams that have made no progress within the configured
    /// interval. Production also schedules this automatically, so an abandoned
    /// final stream cannot remain allocated when no further packets arrive.
    @discardableResult
    func pruneExpired() -> Int {
        let count = pruneExpired(at: now())
        scheduleNextExpiration()
        return count
    }

    @discardableResult
    private func pruneExpired(at instant: ContinuousClock.Instant) -> Int {
        let expiredIds = lastReceivedAt.compactMap { id, receivedAt in
            let age = receivedAt.duration(to: instant)
            return age >= expirationInterval ? id : nil
        }
        for key in expiredIds {
            if let list = receivedPackages[key] {
                // No delivery acknowledgment exists for chunked Messenger
                // transport — a successful local `send()` doesn't mean the
                // relay actually delivered every package to this
                // participant, and there is no NACK/re-request for a
                // specific missing chunk. An incomplete stream previously
                // vanished here with zero evidence it ever happened; at
                // minimum, surface it so a real support/debug session can
                // see it occurred. See CODE_AUDIT_Network §5.2.
                Logger.sharePlay.warning("Chunked ✕: package \(list.id, privacy: .public) from \(key.sourceParticipantId, privacy: .private) expired incomplete: \(list.packageCounter, privacy: .public)/\(list.total, privacy: .public) packages, \(list.receivedByteCount, privacy: .public) bytes received")
            }
            removeStream(key: key)
        }
        return expiredIds.count
    }

    private func makeStreamCapacity(forSource source: UUID) -> Bool {
        while receivedPackages.keys.count(where: { $0.sourceParticipantId == source }) >= maxIncompleteStreamsPerSource {
            guard evictLeastRecentlyActiveStream(preferringSource: source, onlySource: true) else { return false }
        }
        while receivedPackages.count >= maxIncompleteStreams {
            guard evictLeastRecentlyActiveStream(preferringSource: source, onlySource: true) else { return false }
        }
        return true
    }

    private func makeCumulativeCapacity(
        for additionalByteCount: Int,
        excluding key: SharePlayPackageStreamKey?,
        preferringSource source: UUID
    ) -> Bool {
        while incompleteByteCount(ofSource: source) > maxSourceByteCount - additionalByteCount {
            guard evictLeastRecentlyActiveStream(excluding: key, preferringSource: source, onlySource: true) else { return false }
        }
        while cumulativeIncompleteByteCount > maxCumulativeByteCount - additionalByteCount {
            guard evictLeastRecentlyActiveStream(excluding: key, preferringSource: source, onlySource: true) else { return false }
        }
        return true
    }

    private func incompleteByteCount(ofSource source: UUID) -> Int {
        receivedPackages.reduce(0) { total, entry in
            entry.key.sourceParticipantId == source ? total + entry.value.receivedByteCount : total
        }
    }

    @discardableResult
    private func evictLeastRecentlyActiveStream(
        excluding excludedKey: SharePlayPackageStreamKey? = nil,
        preferringSource source: UUID? = nil,
        onlySource: Bool = false
    ) -> Bool {
        let candidates = activityOrder.filter { $0.key != excludedKey }
        // Evict from the participant making room first, so it cannot displace others' transfers.
        let ownCandidates = candidates.filter { $0.key.sourceParticipantId == source }
        let pool = (!ownCandidates.isEmpty || onlySource) ? ownCandidates : candidates
        guard let oldestKey = pool.min(by: { $0.value < $1.value })?.key
        else { return false }
        removeStream(key: oldestKey)
        return true
    }

    private func recordActivity(
        for key: SharePlayPackageStreamKey,
        at instant: ContinuousClock.Instant
    ) {
        lastReceivedAt[key] = instant
        activityOrder[key] = nextActivityOrder
        nextActivityOrder &+= 1
    }

    private func removeStream(key: SharePlayPackageStreamKey) {
        if let removed = receivedPackages.removeValue(forKey: key) {
            cumulativeIncompleteByteCount -= removed.receivedByteCount
        }
        lastReceivedAt.removeValue(forKey: key)
        firstReceivedAt.removeValue(forKey: key)
        activityOrder.removeValue(forKey: key)
    }

    /// One sleeping task serves every stream. Progress only moves the earliest deadline later,
    /// so a task that wakes up early finds nothing expired and schedules the real deadline; no
    /// task is cancelled and created per chunk (about 1,000 for a 64 MB stream).
    /// See CODE_AUDIT_Game_Shareplay §7.3.
    private func scheduleNextExpiration() {
        guard let nextReceivedAt = lastReceivedAt.values.min() else {
            expirationTask?.cancel()
            expirationTask = nil
            scheduledExpiration = nil
            return
        }

        let deadline = nextReceivedAt.advanced(by: expirationInterval)
        if expirationTask != nil, let scheduledExpiration, scheduledExpiration <= deadline {
            return
        }
        expirationTask?.cancel()
        let delay = now().duration(to: deadline)
        let sleep = self.sleep
        scheduledExpiration = deadline
        expirationTask = Task { @MainActor [weak self] in
            do {
                if delay > .zero {
                    try await sleep(delay)
                }
                try Task.checkCancellation()
            } catch {
                return
            }
            guard let self else { return }
            self.expirationTask = nil
            self.scheduledExpiration = nil
            _ = self.pruneExpired(at: self.now())
            self.scheduleNextExpiration()
        }
    }
}

@MainActor
final class PackageMessageList {
    init(initialPackage: PackageMessage) {
        self.id = initialPackage.uuid
        self.total = initialPackage.total
        if let data = initialPackage.data {
            self.messages = [initialPackage.count: data]
            self.receivedByteCount = data.count
        } else {
            self.messages = [:]
            self.receivedByteCount = 0
        }
    }

    let id: UUID
    let total: Int
    private var messages: [Int: Data]
    private(set) var receivedByteCount: Int

    var packageCounter: Int {
        messages.count
    }

    var isComplete: Bool {
        packageCounter == total
    }

    /// Returns the number of newly retained bytes. `0` is an exact retry and
    /// `nil` is a malformed/conflicting package.
    func additionalByteCount(for package: PackageMessage) -> Int? {
        guard package.uuid == id,
              package.total == total,
              (1...total).contains(package.count),
              let data = package.data
        else { return nil }
        guard let existing = messages[package.count] else { return data.count }
        return existing == data ? 0 : nil
    }

    @discardableResult
    func insert(package: PackageMessage) -> Bool {
        guard let additionalByteCount = additionalByteCount(for: package),
              additionalByteCount > 0,
              let data = package.data
        else { return false }
        messages[package.count] = data
        receivedByteCount += additionalByteCount
        return true
    }

    func completedPackage(sourceParticipantId: UUID) -> SharePlayCompletedPackage {
        let chunks = (1...total).compactMap { messages[$0] }
        return SharePlayCompletedPackage(
            id: id,
            sourceParticipantId: sourceParticipantId,
            chunks: chunks,
            byteCount: receivedByteCount
        )
    }
}
