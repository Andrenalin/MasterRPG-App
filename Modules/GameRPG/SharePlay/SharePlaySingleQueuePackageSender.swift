// @copyright André Trettin

import Foundation

enum SharePlayPackageSenderError: Error, Equatable {
    case queueFull
    case messageTooLarge
    case senderStopped
}

/// Serializes complete Messenger payloads. GroupSessionMessenger preserves the
/// order of individual sends, but actor reentrancy used to let two `send` calls
/// alternate their chunks whenever the first call suspended. This queue keeps
/// one payload active until every one of its packages has finished.
@MainActor final class SharePlaySingleQueuePackageSender {
    init(
        packageSize: Int = SharePlaySingleQueuePackageSender.packageSize,
        retryDelays: [Duration] = SharePlaySingleQueuePackageSender.defaultRetryDelays,
        maxOutstandingMessages: Int = SharePlaySingleQueuePackageSender.maxOutstandingMessages,
        maxOutstandingBytes: Int = SharePlaySingleQueuePackageSender.maxOutstandingBytes,
        maxMessageByteCount: Int = SharePlaySingleQueuePackageSender.maxMessageByteCount,
        sendPackage: @escaping (PackageMessage, UUID?) async throws -> Void
    ) {
        self.packageSize = max(1, packageSize)
        self.retryDelays = retryDelays
        self.maxOutstandingMessages = max(1, maxOutstandingMessages)
        self.maxMessageByteCount = max(1, maxMessageByteCount)
        self.maxOutstandingBytes = max(self.maxMessageByteCount, maxOutstandingBytes)
        self.sendPackage = sendPackage
    }

    convenience init(
        packageSize: Int = SharePlaySingleQueuePackageSender.packageSize,
        retryDelays: [Duration] = SharePlaySingleQueuePackageSender.defaultRetryDelays,
        maxOutstandingMessages: Int = SharePlaySingleQueuePackageSender.maxOutstandingMessages,
        maxOutstandingBytes: Int = SharePlaySingleQueuePackageSender.maxOutstandingBytes,
        maxMessageByteCount: Int = SharePlaySingleQueuePackageSender.maxMessageByteCount,
        sendPackage: @escaping (PackageMessage) async throws -> Void
    ) {
        self.init(
            packageSize: packageSize,
            retryDelays: retryDelays,
            maxOutstandingMessages: maxOutstandingMessages,
            maxOutstandingBytes: maxOutstandingBytes,
            maxMessageByteCount: maxMessageByteCount
        ) { package, _ in
            try await sendPackage(package)
        }
    }

    private struct Request {
        let id: UUID
        let streamId: UUID
        let data: Data
        let participantId: UUID?
    }

    private let packageSize: Int
    private let retryDelays: [Duration]
    private let maxOutstandingMessages: Int
    private let maxOutstandingBytes: Int
    private let maxMessageByteCount: Int
    private let sendPackage: (PackageMessage, UUID?) async throws -> Void

    private var pendingRequests: [Request] = []
    private var activeRequest: Request?
    private var continuations: [UUID: CheckedContinuation<Void, any Error>] = [:]
    private var cancelledRequestIds: Set<UUID> = []
    private var outstandingByteCount = 0
    private var workerTask: Task<Void, Never>?
    private var isStopped = false

    // Apple's guidance for GroupSessionMessenger.send(_:to:) is that "small
    // messages can include up to 256 kilobytes of data". `Data` expands when
    // Codable encodes it as Base64, and JSON escaping can double slash-heavy
    // Base64 output: a worst-case 128 KB chunk encodes to about 341 KB. 64 KB
    // keeps that same worst case near 171 KB and leaves transport headroom.
    nonisolated static let packageSize = 64_000
    nonisolated static let encodedMessageSizeLimit = 256_000
    nonisolated static let defaultRetryDelays: [Duration] = [.milliseconds(100), .milliseconds(300)]
    nonisolated static let lowPackageCount = 60
    nonisolated static let throttleInMilliSeconds = 200
    nonisolated static let maxOutstandingMessages = 16
    nonisolated static let maxOutstandingBytes = 128_000_000
    nonisolated static let maxMessageByteCount = 64_000_000

    func send(data: Data, participantId: UUID? = nil) async throws {
        guard !isStopped else { throw SharePlayPackageSenderError.senderStopped }
        guard data.count <= maxMessageByteCount else {
            throw SharePlayPackageSenderError.messageTooLarge
        }
        guard outstandingMessageCount < maxOutstandingMessages,
              outstandingByteCount <= maxOutstandingBytes - data.count
        else {
            throw SharePlayPackageSenderError.queueFull
        }

        let request = Request(
            id: UUID(),
            streamId: UUID(),
            data: data,
            participantId: participantId
        )

        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, any Error>) in
                guard !Task.isCancelled else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                continuations[request.id] = continuation
                pendingRequests.append(request)
                outstandingByteCount += data.count
                startWorkerIfNeeded()
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.cancel(requestId: request.id)
            }
        }
    }

    /// Cancels the session-owned worker and every caller waiting on this
    /// sender. A stopped sender is deliberately not reusable across sessions.
    func cancelAll() {
        guard !isStopped else { return }
        isStopped = true
        workerTask?.cancel()
        workerTask = nil
        let currentContinuations = continuations.values
        continuations = [:]
        pendingRequests = []
        activeRequest = nil
        cancelledRequestIds = []
        outstandingByteCount = 0
        currentContinuations.forEach { $0.resume(throwing: CancellationError()) }
    }

    nonisolated func packageCount(for data: Data) -> Int {
        guard !data.isEmpty else { return 1 }
        return (data.count + packageSize - 1) / packageSize
    }

    private var outstandingMessageCount: Int {
        pendingRequests.count + (activeRequest == nil ? 0 : 1)
    }

    private func startWorkerIfNeeded() {
        guard workerTask == nil else { return }
        workerTask = Task { @MainActor [weak self] in
            await self?.drainQueue()
        }
    }

    private func drainQueue() async {
        while !Task.isCancelled, !isStopped, !pendingRequests.isEmpty {
            let request = pendingRequests.removeFirst()
            activeRequest = request

            do {
                try await send(request: request)
                finish(request: request, result: .success(()))
            } catch {
                finish(request: request, result: .failure(error))
            }
        }
        activeRequest = nil
        workerTask = nil
    }

    /// Produces and sends one chunk at a time. Only the active chunk and the
    /// original payload are materialized, independent of package count.
    private func send(request: Request) async throws {
        let total = packageCount(for: request.data)
        guard !request.data.isEmpty else {
            try checkCancellation(of: request.id)
            try await sendWithRetry(
                PackageMessage(uuid: request.streamId, count: 1, total: 1, data: Data()),
                requestId: request.id,
                participantId: request.participantId
            )
            return
        }

        var packageNumber = 1
        var offset = 0
        while offset < request.data.count {
            try checkCancellation(of: request.id)
            let end = min(offset + packageSize, request.data.count)
            let package = PackageMessage(
                uuid: request.streamId,
                count: packageNumber,
                total: total,
                data: request.data[offset..<end]
            )
            try await sendWithRetry(
                package,
                requestId: request.id,
                participantId: request.participantId
            )
            packageNumber += 1
            offset = end
            if packageNumber > 1,
               (packageNumber - 1) % Self.lowPackageCount == 0,
               offset < request.data.count {
                try await Task.sleep(for: .milliseconds(Self.throttleInMilliSeconds))
            }
        }
    }

    private func sendWithRetry(
        _ package: PackageMessage,
        requestId: UUID,
        participantId: UUID?
    ) async throws {
        var retryIndex = 0
        while true {
            try checkCancellation(of: requestId)
            do {
                try await sendPackage(package, participantId)
                try checkCancellation(of: requestId)
                return
            } catch let error as CancellationError {
                throw error
            } catch {
                guard retryIndex < retryDelays.count else { throw error }
                let delay = retryDelays[retryIndex]
                retryIndex += 1
                try await Task.sleep(for: delay)
            }
        }
    }

    private func checkCancellation(of requestId: UUID) throws {
        try Task.checkCancellation()
        if cancelledRequestIds.contains(requestId) {
            throw CancellationError()
        }
    }

    private func cancel(requestId: UUID) {
        guard continuations[requestId] != nil else { return }
        if activeRequest?.id == requestId {
            cancelledRequestIds.insert(requestId)
            continuations.removeValue(forKey: requestId)?.resume(throwing: CancellationError())
            return
        }
        guard let index = pendingRequests.firstIndex(where: { $0.id == requestId }) else { return }
        let request = pendingRequests.remove(at: index)
        outstandingByteCount -= request.data.count
        continuations.removeValue(forKey: requestId)?.resume(throwing: CancellationError())
    }

    private func finish(request: Request, result: Result<Void, any Error>) {
        // `cancelAll()` already clears the active request and byte accounting.
        // A suspended messenger send can still unwind afterward; ignore that
        // stale completion instead of subtracting the payload a second time.
        guard activeRequest?.id == request.id else { return }
        outstandingByteCount = max(0, outstandingByteCount - request.data.count)
        cancelledRequestIds.remove(request.id)
        activeRequest = nil
        guard let continuation = continuations.removeValue(forKey: request.id) else { return }
        continuation.resume(with: result)
    }
}
