// @copyright André Trettin

import CoreRPG
import Foundation
import os.log

// The message-origin/dedup-key/pipeline actor — split out of
// GameNetworkModel.swift. See CODE_AUDIT §9.10.

enum GameMessageOrigin: Hashable, Sendable {
    case direct(ConnectionController.ID?)
    case proxy(ConnectionController.ID?)
    case sharePlay(UUID)
    case file
    case local

    var connectionId: ConnectionController.ID? {
        switch self {
        case let .direct(connectionId), let .proxy(connectionId):
            connectionId
        case .sharePlay, .file, .local:
            nil
        }
    }

    var sharePlayParticipantId: UUID? {
        guard case let .sharePlay(participantId) = self else { return nil }
        return participantId
    }

    /// Identity used only to associate a transport peer with its game player so
    /// disconnect cleanup works for both Bonjour and SharePlay. It must not be
    /// reused as a physical response route.
    var participantConnectionId: UUID? {
        switch self {
        case let .direct(connectionId), let .proxy(connectionId):
            connectionId
        case let .sharePlay(participantId):
            participantId
        case .file, .local:
            nil
        }
    }

    var isProxy: Bool {
        guard case .proxy = self else { return false }
        return true
    }

    var usesSharePlayFileTransport: Bool {
        switch self {
        case .sharePlay, .file:
            true
        case .direct, .proxy, .local:
            false
        }
    }
}

struct GameMessageKey: Hashable, Sendable {
    let senderId: UUID
    let counter: Int
    let proxyCounter: Int
    let type: RPGMessageType
    let subType: RPGMessageActionType
    let dataId: UUID
    let dataType: NetworkModules
    let dataVersion: Int
    let targetId: UUID?
    /// The reference and the package of one show share every other field: payload presence
    /// keeps the bytes from being dropped as a duplicate of the reference.
    let hasData: Bool

    init(model: GameNetworkModel) {
        senderId = model.sender.id
        counter = model.counter
        proxyCounter = model.proxyCounter
        type = model.type
        subType = model.subType
        dataId = model.data.id
        dataType = model.data.type
        dataVersion = model.data.version
        targetId = model.targetId
        hasData = model.data.data != nil
    }
}

struct GameMessageEvent: Sendable {
    let model: GameNetworkModel
    let origin: GameMessageOrigin

    var connectionId: ConnectionController.ID? {
        origin.connectionId
    }

    var fromProxy: Bool {
        origin.isProxy
    }

    /// Payload bytes the event retains while queued.
    var payloadBytes: Int {
        model.data.data?.count ?? 0
    }

    var deduplicationKey: GameMessageKey? {
        guard !model.isAcknowledgement, model.counter > 0 else { return nil }
        return GameMessageKey(model: model)
    }
}

/// Distinguishes *why* `GameMessagePipeline.enqueue(_:)` did not admit an
/// event. Before this type existed, "already seen" and "queue at capacity"
/// both answered `false`, so a genuinely new message dropped under load was
/// logged and treated identically to an ordinary duplicate, with no signal
/// that anything was actually lost. See CODE_AUDIT_Network §5.14.
enum GameMessageEnqueueResult: Sendable, Equatable {
    case enqueued
    case duplicate
    case queueFull
    case pipelineStopped

    var isAccepted: Bool {
        self == .enqueued
    }
}

/// The pipelines whose drain worker the current task runs inside of (directly or through awaited
/// handlers). A handler that submits to a pipeline it already runs inside must not wait for its
/// own message: the worker is busy with the handler, so the wait would never end.
enum GameMessageDrainContext {
    @TaskLocal static var activePipelines: Set<ObjectIdentifier> = []
}

actor GameMessagePipeline {
    private struct Waiter {
        let id: Int
        let ticket: Int
        let continuation: CheckedContinuation<Void, Never>
    }

    private let recentLimit: Int
    /// Unlike `recentKeys`, `messages` itself had no cap — each element
    /// retains a full `GameNetworkModel`, megabytes for a map/photo/pdf/space
    /// package, so a producer faster than the consumer (a SharePlay journal
    /// burst, or a peer sending distinct-counter payloads on purpose) could
    /// accumulate unbounded memory. See CODE_AUDIT_Game §7.4.
    private let maximumQueuedMessages: Int
    private var messages: [GameMessageEvent] = []
    /// Bumped by `reset()` and `cancelAll()`. An event dequeued before the bump belongs to the
    /// session that was reset, and its drain may still be suspended in its handler.
    private var generation = 0
    /// The generation of the event a drain has dequeued and not yet reported back, `nil` when
    /// no event is in hand. Only the drain that owns the event clears it: `reset()` used to
    /// clear the busy flag itself, so the next enqueue started a second drain next to a
    /// handler still importing for the old session, and that handler's `processed` then
    /// cleared the flag under the second drain. See CODE_AUDIT_21 §3.9.
    private var inFlightGeneration: Int?
    private var isCancelled = false
    /// Events admitted so far, and events that have left the queue for good (processed, or
    /// discarded by `reset()`/`cancelAll()`). Events are handled strictly in the order they were
    /// admitted, so the event admitted as number `n` is finished once `finishedCount >= n`.
    private var admittedCount = 0
    private var finishedCount = 0
    private var waiters: [Waiter] = []
    private var nextWaiterId = 0
    /// The one task that drains `messages`. Owned here, not by whichever peer's receive task
    /// enqueued first, so a peer disconnecting (cancelling its receive task) cannot cancel the
    /// handling of another peer's message. Only `cancelAll()` cancels it. See CODE_AUDIT_Game_Shareplay §3.1.
    private var drainTask: Task<Void, Never>?
    private var isDraining = false
    private var recentKeys: [GameMessageKey] = []
    private var recentKeySet: Set<GameMessageKey> = []
    private var pendingKeySet: Set<GameMessageKey> = []
    /// Keys of events the game master has already decided to relay. `enqueue` records a key only
    /// after the relay's own awaits, so two copies handled at the same time would both pass
    /// `hasSeen`; `reserveRelay` closes that gap. Bounded like `recentKeys`.
    private var relayedKeys: [GameMessageKey] = []
    private var relayedKeySet: Set<GameMessageKey> = []
    private var currentKey: GameMessageKey?
    /// The full event `next()` most recently dequeued, retained only so a
    /// cancelled drain (`requeueCurrentOnCancellation()`) can restore it
    /// instead of losing it. Cleared by every `processed`/requeue path.
    private var currentEvent: GameMessageEvent?

    init(recentLimit: Int = 256, maximumQueuedMessages: Int = 128) {
        self.recentLimit = recentLimit
        self.maximumQueuedMessages = maximumQueuedMessages
    }

    @discardableResult
    func enqueue(_ event: GameMessageEvent) -> GameMessageEnqueueResult {
        guard !isCancelled else { return .pipelineStopped }
        guard messages.count < maximumQueuedMessages else { return .queueFull }
        // Count alone lets a few hundred-MB messages with distinct counters push memory into the
        // GB range. An empty queue always admits one message, however large.
        // See CODE_AUDIT_16 §6.3.
        if !messages.isEmpty {
            let queuedBytes = messages.reduce(0) { $0.saturatingAdding($1.payloadBytes) }
            guard queuedBytes.saturatingAdding(event.payloadBytes) <= GameLimits.maximumQueuedBytes else { return .queueFull }
        }
        if let key = event.deduplicationKey {
            guard !recentKeySet.contains(key), !pendingKeySet.contains(key) else { return .duplicate }
            pendingKeySet.insert(key)
        }
        messages.append(event)
        admittedCount += 1
        return .enqueued
    }

    /// Enqueues `event` and logs what became of it; `true` when it is queued and the caller
    /// drains the queue. `prefix` names the controller, `kind` the transport (`"file "`).
    func enqueueAndLog(_ event: GameMessageEvent, prefix: String, kind: String = "") -> Bool {
        let model = event.model
        switch enqueue(event) {
        case .enqueued:
            return true
        case .duplicate:
            Logger.networking.debug("\(prefix, privacy: .public): Duplicate \(kind, privacy: .public)ignored \(model.counter, privacy: .public): \(model.type.debugDescription, privacy: .public) - \(model.subType.debugDescription, privacy: .public), \(model.data.type.token, privacy: .public)")
        case .queueFull:
            // Distinct from an ordinary duplicate: a genuinely new message was discarded only
            // because the pipeline is momentarily saturated, not because it was already seen.
            // See CODE_AUDIT_Network §5.14.
            Logger.networking.error("\(prefix, privacy: .public): Message queue full, \(kind, privacy: .public)message lost \(model.counter, privacy: .public): \(model.type.debugDescription, privacy: .public) - \(model.subType.debugDescription, privacy: .public), \(model.data.type.token, privacy: .public)")
        case .pipelineStopped:
            Logger.networking.debug("\(prefix, privacy: .public): Message pipeline stopped, ignoring \(kind, privacy: .public)\(model.counter, privacy: .public)")
        }
        return false
    }

    /// Admits `event` and returns once it has been handled. The queue is drained by the
    /// pipeline's own worker, which runs `drain` (the controller's loop over `next()`); the
    /// caller only waits for its own message, so a slow handler still holds back the peer that
    /// sent the message and nobody else. Cancelling the caller stops the waiting, never the
    /// handling. A duplicate or a rejected message returns at once.
    func submit(
        _ event: GameMessageEvent,
        prefix: String,
        kind: String = "",
        drain: @escaping @Sendable () async -> Void
    ) async {
        guard enqueueAndLog(event, prefix: prefix, kind: kind) else { return }
        let ticket = admittedCount
        startDrainIfNeeded(drain)
        guard !GameMessageDrainContext.activePipelines.contains(ObjectIdentifier(self)) else { return }
        await waitUntilFinished(ticket)
    }

    private func startDrainIfNeeded(_ drain: @escaping @Sendable () async -> Void) {
        guard !isDraining, !isCancelled, !messages.isEmpty else { return }
        isDraining = true
        let active = GameMessageDrainContext.activePipelines.union([ObjectIdentifier(self)])
        drainTask = Task { [weak self] in
            await GameMessageDrainContext.$activePipelines.withValue(active) {
                await drain()
            }
            await self?.drainEnded(restartWith: drain)
        }
    }

    /// The worker left its loop. Normally the queue is empty. A worker that left early (its
    /// task was cancelled by a stop that has been followed by a new game, or a handler that
    /// threw `CancellationError`) leaves messages behind, so a new worker takes them over.
    private func drainEnded(restartWith drain: @escaping @Sendable () async -> Void) {
        isDraining = false
        drainTask = nil
        startDrainIfNeeded(drain)
    }

    private func waitUntilFinished(_ ticket: Int) async {
        guard finishedCount < ticket else { return }
        let id = nextWaiterId
        nextWaiterId += 1
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                guard !Task.isCancelled else {
                    continuation.resume()
                    return
                }
                waiters.append(Waiter(id: id, ticket: ticket, continuation: continuation))
            }
        } onCancel: {
            Task { await self.stopWaiting(id: id) }
        }
    }

    private func stopWaiting(id: Int) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        waiters.remove(at: index).continuation.resume()
    }

    private func resumeFinishedWaiters() {
        let finished = waiters.filter { $0.ticket <= finishedCount }
        guard !finished.isEmpty else { return }
        waiters.removeAll { $0.ticket <= finishedCount }
        for waiter in finished {
            waiter.continuation.resume()
        }
    }

    /// Every queued event, and the one in hand, is gone: nobody has anything left to wait for.
    private func discardAll() {
        finishedCount = admittedCount
        resumeFinishedWaiters()
    }

    /// Whether `event` repeats one that is queued or was processed recently.
    func hasSeen(_ event: GameMessageEvent) -> Bool {
        guard let key = event.deduplicationKey else { return false }
        return recentKeySet.contains(key) || pendingKeySet.contains(key)
    }

    /// Decides in one step, with no await in between, whether `event` may be relayed, and
    /// reserves it: a repeat of one that is queued, was processed or is already being relayed
    /// answers `false`. An event without a deduplication key is always relayed.
    func reserveRelay(_ event: GameMessageEvent) -> Bool {
        guard let key = event.deduplicationKey else { return true }
        guard !recentKeySet.contains(key), !pendingKeySet.contains(key), !relayedKeySet.contains(key) else {
            return false
        }
        relayedKeySet.insert(key)
        relayedKeys.append(key)
        if relayedKeys.count > recentLimit {
            relayedKeySet.remove(relayedKeys.removeFirst())
        }
        return true
    }

    /// Whether events are waiting to be handled.
    var hasQueuedMessages: Bool {
        !messages.isEmpty
    }

    /// The next event, or `nil` while an event is still in hand: also one of a session that was
    /// reset since. Its drain picks up the new messages once its handler has returned.
    func next() -> GameMessageEvent? {
        guard !isCancelled, inFlightGeneration == nil, !messages.isEmpty else { return nil }
        inFlightGeneration = generation
        let event = messages.removeFirst()
        currentKey = event.deduplicationKey
        currentEvent = event
        return event
    }

    func processed(success: Bool) {
        defer { inFlightGeneration = nil }
        // The event of a session that was reset meanwhile: its keys went with the reset.
        guard inFlightGeneration == generation else { return }
        finishedCount += 1
        resumeFinishedWaiters()
        if let currentKey {
            pendingKeySet.remove(currentKey)
            if success {
                remember(currentKey)
            }
        }
        currentKey = nil
        currentEvent = nil
    }

    /// Call instead of `processed(success:)` when the ambient `Task` driving
    /// the drain loop was found cancelled immediately after dequeuing, before
    /// any processing was attempted — restores the event to the front of the
    /// queue so the next real trigger retries it, rather than discarding the
    /// one message that was already pulled off `messages`. Not safe to use
    /// once processing has actually begun (e.g. after side effects like a
    /// proxy forward), since a requeue there would risk re-applying them.
    /// See CODE_AUDIT_Network §5.15.
    func requeueCurrentOnCancellation() {
        defer { inFlightGeneration = nil }
        // Nothing of a reset session goes back into the queue.
        guard inFlightGeneration == generation else { return }
        if let currentEvent {
            messages.insert(currentEvent, at: 0)
        }
        if let currentKey {
            pendingKeySet.remove(currentKey)
        }
        currentKey = nil
        currentEvent = nil
    }

    func cancelAll() {
        drainTask?.cancel()
        messages.removeAll()
        generation += 1
        isCancelled = true
        recentKeys.removeAll()
        recentKeySet.removeAll()
        pendingKeySet.removeAll()
        relayedKeys.removeAll()
        relayedKeySet.removeAll()
        currentKey = nil
        currentEvent = nil
        discardAll()
    }

    func reset() {
        messages.removeAll()
        generation += 1
        isCancelled = false
        recentKeys.removeAll()
        recentKeySet.removeAll()
        pendingKeySet.removeAll()
        relayedKeys.removeAll()
        relayedKeySet.removeAll()
        currentKey = nil
        currentEvent = nil
        discardAll()
    }

    private func remember(_ key: GameMessageKey) {
        recentKeys.append(key)
        recentKeySet.insert(key)

        while recentKeys.count > recentLimit {
            let removed = recentKeys.removeFirst()
            recentKeySet.remove(removed)
        }
    }
}

extension GameNetworkModel: CustomDebugStringConvertible {
    var debugDescription: String {
        "counter \(counter) type: \(type) - \(subType), game: \(sender.name) data: \(data.id) \(data.type.token)"
    }
}

extension GameNetworkModel {
    var senderType: GameType { sender.role }
    var senderName: String { sender.name }
}

extension GameNetworkModel: MessageMapper {
    // NetworkCodableDataType stores file bytes as Base64. Escaping every slash can nearly
    // double valid Base64 output and unnecessarily halves the Messenger fallback limit. All
    // supported decoders accept literal JSON slashes, so keep the canonical payload compact.
    // Allocated once per process instead of per call — see CODE_AUDIT §7.4. This encoder's
    // custom `outputFormatting` means it can't share `JSONCoding.encoder`'s plain instance.
    private static let outboundEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        return encoder
    }()

    static func decodeData(of data: Data?) -> GameNetworkModel? {
        guard let data else { return nil }
        do {
            return try JSONCoding.decoder.decode(GameNetworkModel.self, from: data)
        } catch {
            Logger.networking.error("GameNetworkModel: Failed to decode inbound message: \(error.logIdentifier, privacy: .public) \(error.localizedDescription, privacy: .private)")
        }
        return nil
    }

    func encodeData() -> Data? {
        try? Self.outboundEncoder.encode(self)
    }

    /// LAN messages can carry multi-megabyte Base64 attachments; decoding them on the main actor
    /// hitched the UI on every large push. The SharePlay path already keeps the same work off
    /// main (`RPGSharePlayController.decodedMessage`). See CODE_AUDIT_15 §3.2.
    @concurrent
    static func decodedOffMain(of data: Data?) async -> GameNetworkModel? {
        guard !Task.isCancelled else { return nil }
        return decodeData(of: data)
    }
}

/// Wraps bytes that are already encoded, so a relay can forward a received frame untouched
/// instead of decoding and re-encoding it. See CODE_AUDIT_17 §7.2.
struct PreEncodedMessage: MessageMapper {
    let bytes: Data

    func encodeData() -> Data? { bytes }
    static func decodeData(of data: Data?) -> PreEncodedMessage? { data.map(PreEncodedMessage.init(bytes:)) }
}

/// Encodes a message off the main actor; see `GameNetworkModel.decodedOffMain(of:)`.
@concurrent
func encodedOffMain(_ message: (any MessageMapper)?) async -> Data? {
    guard !Task.isCancelled else { return nil }
    return message?.encodeData()
}

private extension Int {
    func saturatingAdding(_ other: Int) -> Int {
        let (sum, overflow) = addingReportingOverflow(other)
        return overflow ? Int.max : sum
    }
}
