// @copyright André Trettin

#if canImport(Testing)
import AdventureRPG
import CoreRPG
import Foundation
import RPGResourcesDebug
import Testing

@testable import AudioRPG
@testable import GameRPG

/// CODE_AUDIT_Game_Shareplay §7.1 (Journal load ordering), §7.2 (package cache), §7.3 (receiver
/// chunks and expiry) and §7.5 (byte budget table).
@MainActor
private final class Gate {
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var isOpen = false
    private(set) var entered = false

    func wait() async {
        entered = true
        guard !isOpen else { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func open() {
        isOpen = true
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
private final class Log {
    var events: [String] = []
}

@MainActor
private func eventually(_ condition: @MainActor () -> Bool) async -> Bool {
    await awaitCondition(pollInterval: .milliseconds(5)) { condition() }
}

// MARK: - 7.1 Journal load sequencer

@Suite("Journal load sequencer (§7.1)")
@MainActor
struct SharePlayJournalLoadSequencerTests {
    typealias Load = SharePlayJournalLoadSequencer.Load

    @Test("The first batch keeps the message order")
    func firstBatchKeepsOrder() async {
        let sequencer = SharePlayJournalLoadSequencer()
        let log = Log()
        let gate = Gate()
        let a = UUID(), b = UUID(), c = UUID()

        sequencer.start([
            Load(a) { log.events.append("a start"); await gate.wait(); log.events.append("a end") },
            Load(b) { log.events.append("b") },
            Load(c) { log.events.append("c") }
        ], isCurrent: { true })
        let aStarted = await eventually { gate.entered }
        #expect(aStarted)
        // b and c wait for a, in front of them.
        #expect(log.events == ["a start"])

        gate.open()
        let done = await eventually { log.events.count == 4 }

        #expect(done)
        #expect(log.events == ["a start", "a end", "b", "c"])
    }

    @Test("A later publication of an item waits for that item, not for the whole batch")
    func laterPublicationDoesNotWaitForTheBatch() async {
        let sequencer = SharePlayJournalLoadSequencer()
        let log = Log()
        let first = Gate()
        let second = Gate()
        let x = UUID(), y = UUID()

        // The batch: x, then y, whose load is slow.
        sequencer.start([
            Load(x) { await first.wait(); log.events.append("x1") },
            Load(y) { await second.wait(); log.events.append("y1") }
        ], isCurrent: { true })
        // A newer publication of x arrives while y still loads.
        sequencer.start([Load(x) { log.events.append("x2") }], isCurrent: { true })

        first.open()
        let x2Ran = await eventually { log.events.contains("x2") }

        #expect(x2Ran)
        #expect(!log.events.contains("y1"))
        #expect(log.events.filter { $0.hasPrefix("x") } == ["x1", "x2"])

        second.open()
        let all = await eventually { log.events.contains("y1") }
        #expect(all)
    }

    @Test("Later snapshots load their items side by side")
    func laterSnapshotsAreConcurrent() async {
        let sequencer = SharePlayJournalLoadSequencer()
        let log = Log()
        let slow = Gate()
        let a = UUID(), b = UUID()
        // The first snapshot is the join batch.
        sequencer.start([Load(UUID()) { log.events.append("join") }], isCurrent: { true })
        _ = await eventually { log.events == ["join"] }

        sequencer.start([
            Load(a) { await slow.wait(); log.events.append("a") },
            Load(b) { log.events.append("b") }
        ], isCurrent: { true })
        let bRan = await eventually { log.events.contains("b") }

        #expect(bRan)
        #expect(!log.events.contains("a"))
        slow.open()
    }

    @Test("A newer load of the same item waits for the older one")
    func sameItemKeepsOrder() async {
        let sequencer = SharePlayJournalLoadSequencer()
        let log = Log()
        let gate = Gate()
        let item = UUID()
        sequencer.start([Load(UUID()) { }], isCurrent: { true })

        sequencer.start([Load(item) { await gate.wait(); log.events.append("old") }], isCurrent: { true })
        sequencer.start([Load(item) { log.events.append("new") }], isCurrent: { true })
        _ = await eventually { gate.entered }
        #expect(log.events.isEmpty)

        gate.open()
        let done = await eventually { log.events.count == 2 }
        #expect(done)
        #expect(log.events == ["old", "new"])
    }

    @Test("A load of an ended session does not run, and cancelling forgets the batch")
    func endedSessionAndCancel() async {
        let sequencer = SharePlayJournalLoadSequencer()
        let log = Log()
        let item = UUID()

        sequencer.start([Load(item) { log.events.append("ran") }], isCurrent: { false })
        let ended = await eventually { sequencer.activeItemCount == 0 }
        #expect(ended)
        #expect(log.events.isEmpty)

        let gate = Gate()
        sequencer.start([Load(item) { await gate.wait() }], isCurrent: { true })
        _ = await eventually { gate.entered }
        sequencer.cancelAll()
        #expect(sequencer.activeItemCount == 0)
        gate.open()
    }
}

// MARK: - 7.2 Package cache

@Suite("Master package cache (§7.2)")
@MainActor
struct MasterPackageCacheTests {
    private func package(_ id: UUID = UUID(), version: Int = 1, bytes: Int = 4, type: NetworkModules = .photo) -> NetworkCodableDataType {
        NetworkCodableDataType(id: id, type: type, version: version, data: Data(count: bytes))
    }

    @Test("A package is reused for the version it was made for")
    func reuseForTheSameVersion() {
        var cache = MasterPackageCache()
        let item = package(version: 5)
        cache.store(item)

        let hit = cache.package(for: .photo, itemId: item.id, matching: MasterPackageFingerprint(version: 5))

        #expect(hit == item)
        #expect(cache.hitCount == 1)
    }

    @Test("An edit changes the fingerprint and drops the package")
    func editInvalidates() {
        var cache = MasterPackageCache()
        let item = package(version: 5)
        cache.store(item)

        let hit = cache.package(for: .photo, itemId: item.id, matching: MasterPackageFingerprint(version: 6))

        #expect(hit == nil)
        #expect(cache.count == 0)
    }

    @Test("A map is valid for its version, asset version and content version together")
    func mapFingerprint() {
        var cache = MasterPackageCache()
        let map = NetworkCodableDataType(id: UUID(), type: .map, version: 1, data: Data([1]), assetVersion: 2, contentVersion: 3)
        cache.store(map)

        let otherContent = cache.package(for: .map, itemId: map.id, matching: MasterPackageFingerprint(version: 1, assetVersion: 2, contentVersion: 4))
        #expect(otherContent == nil)

        cache.store(map)
        let same = cache.package(for: .map, itemId: map.id, matching: MasterPackageFingerprint(map))
        #expect(same == map)
    }

    @Test("Only the newest two packages are kept")
    func entryLimit() {
        var cache = MasterPackageCache()
        let first = package(), second = package(), third = package()
        cache.store(first)
        cache.store(second)
        cache.store(third)

        #expect(cache.count == MasterPackageCache.maximumEntries)
        let evicted = cache.package(for: .photo, itemId: first.id, matching: MasterPackageFingerprint(first))
        #expect(evicted == nil)
    }

    @Test("A package over the size of one frame, or without bytes, is not kept")
    func sizeLimit() {
        var cache = MasterPackageCache()
        cache.store(package(bytes: MasterPackageCache.maximumByteCount + 1))
        cache.store(NetworkCodableDataType(id: UUID(), type: .photo, version: 1, data: nil))
        #expect(cache.count == 0)
    }

    @Test("Players that ask for the same item cost one export")
    func playersShareOneExport() async throws {
        // Given: two players that lack the photo.
        let env = try await LinkedGameEnvironment.create()
        try await env.importData(named: ReportedFileModule.photo.fixture, into: env.masterRoot)
        env.masterRoot.adventureRoot.startGame()
        for index in 1 ... 2 {
            let player = try await env.addPlayer(named: "Player \(index)")
            player.root.adventureRoot.startGame()
        }
        for player in env.players {
            await env.ready(player)
        }
        env.clearHistory()
        let itemId = try ReportedFileModule.photo.fileItemId(in: env.masterRoot)
        let share = await ReportedFileModule.photo.controllable(in: env.masterRoot).share(id: itemId)

        // When: the game master shows it, and the second player asks for it again as well.
        await env.master.show(for: share)
        await env.settle()
        let exported = env.master.gameModel.packageCache.count
        let secondPlayer = env.players[1]
        let again = try await env.master.cachedPackage(
            module: .photo,
            itemId: itemId,
            controllable: ReportedFileModule.photo.controllable(in: env.masterRoot)
        )

        // Then: the export was kept and handed out again.
        #expect(exported == 1)
        #expect((again.data?.count ?? 0) > 0)
        #expect(env.master.gameModel.packageCache.hitCount >= 1)
        #expect(await ReportedFileModule.photo.controllable(in: secondPlayer.root).currentId == itemId)
    }

    @Test("An audio asset request is answered from the package the push exported (Game_Photo_Audio §3.2)")
    func audioRequestsShareOneExport() async throws {
        // Given: a game master with an audio file.
        let env = try await LinkedGameEnvironment.create()
        try await env.importData(named: ResourcesDebug.audioTestData, into: env.masterRoot)
        env.masterRoot.adventureRoot.startGame()
        let audioId = try #require(env.masterRoot.audioRoot.gameControllable.itemControllable.itemDataModel.items.first)

        // When: the package is exported once and two players then ask for it.
        let exported = try await env.master.audioPackage(for: audioId)
        let hitsBefore = env.master.gameModel.packageCache.hitCount
        let first = try await env.master.audioPackage(for: audioId)
        let second = try await env.master.audioPackage(for: audioId)

        // Then: the requests are answered from the cache, with the same bytes.
        #expect((exported.data?.count ?? 0) > 0)
        #expect(first == exported)
        #expect(second == exported)
        #expect(env.master.gameModel.packageCache.hitCount == hitsBefore + 2)
    }
}

// MARK: - 7.3 Receiver

@Suite("Package receiver (§7.3)")
@MainActor
struct PackageReceiverPerformanceTests {
    private let source = UUID()

    @Test("A stream of many chunks sleeps once, not once per chunk")
    func oneExpiryTaskForManyChunks() async {
        // Given
        let counter = SleepCounter()
        let receiver = SharePlayPackageReceiver(
            expirationInterval: .seconds(30),
            sleep: { duration in await counter.sleep(for: duration) }
        )
        let streamId = UUID()

        // When
        for index in 1 ... 200 {
            _ = receiver.received(
                package: PackageMessage(uuid: streamId, count: index, total: 1_000, data: Data(count: 8)),
                from: source
            )
        }
        for _ in 0 ..< 20 { await Task.yield() }

        // Then
        #expect(counter.calls == 1)
        receiver.reset()
    }

    @Test("The assembled package lets go of its chunks")
    func chunksAreReleased() {
        let package = SharePlayCompletedPackage(
            id: UUID(),
            sourceParticipantId: source,
            chunks: [Data("ab".utf8), Data("cd".utf8)],
            byteCount: 4
        )

        let data = package.takeReassembledData()

        #expect(data == Data("abcd".utf8))
        #expect(package.chunks.isEmpty)
    }
}

@MainActor
private final class SleepCounter {
    private(set) var calls = 0
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func sleep(for duration: Duration) async {
        calls += 1
        await withCheckedContinuation { continuations.append($0) }
    }
}

// MARK: - 7.5 Budget table

@Suite("Inbound byte budget table (§7.5)")
@MainActor
struct InboundByteBudgetTableTests {
    @Test("A sender is forgotten once its bytes left the window")
    func senderIsForgotten() {
        var budget = SharePlayInboundByteBudget()
        let start = ContinuousClock.now
        for _ in 0 ..< 10 {
            _ = budget.admit(1, from: UUID(), now: start)
        }
        #expect(budget.senderCount == 10)

        // A minute later another sender sends: the earlier ones are gone.
        _ = budget.admit(1, from: UUID(), now: start.advanced(by: SharePlayInboundByteBudget.window))

        #expect(budget.senderCount == 1)
    }

    @Test("A sender that gave everything back is forgotten")
    func releasedSenderIsForgotten() {
        var budget = SharePlayInboundByteBudget()
        let sender = UUID()
        _ = budget.admit(100, from: sender)

        budget.release(100, from: sender)

        #expect(budget.senderCount == 0)
    }
}
#endif
