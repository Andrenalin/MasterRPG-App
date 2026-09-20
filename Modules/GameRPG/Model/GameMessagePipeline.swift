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
    let messageID: UUID?
    let senderId: UUID
    let counter: Int
    let proxyCounter: Int
    let type: RPGMessageType
    let subType: RPGMessageActionType
    let dataId: UUID
    let dataType: NetworkModules
    let dataVersion: Int
    let purpose: GameMessagePurpose
    /// A metadata-only delivery (failed journal transfer) and the later full
    /// payload share every other field — payload presence keeps the real bytes
    /// from being dropped as a duplicate.
    let hasData: Bool

    init(model: GameNetworkModel) {
        messageID = model.messageID
        senderId = model.sender.id
        counter = model.counter
        proxyCounter = model.proxyCounter
        type = model.type
        subType = model.subType
        dataId = model.data.id
        dataType = model.data.type
        dataVersion = model.data.version
        purpose = model.purpose
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

    var deduplicationKey: GameMessageKey? {
        guard model.subType != .ok,
              model.subType != .failed
        else { return nil }
        guard model.messageID != nil || model.counter > 0 else { return nil }
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

actor GameMessagePipeline {
    private let recentLimit: Int
    /// Unlike `recentKeys`, `messages` itself had no cap — each element
    /// retains a full `GameNetworkModel`, megabytes for a map/photo/pdf/space
    /// package, so a producer faster than the consumer (a SharePlay journal
    /// burst, or a peer sending distinct-counter payloads on purpose) could
    /// accumulate unbounded memory. See CODE_AUDIT_Game §7.4.
    private let maximumQueuedMessages: Int
    private var messages: [GameMessageEvent] = []
    private var processing = false
    private var isCancelled = false
    private var recentKeys: [GameMessageKey] = []
    private var recentKeySet: Set<GameMessageKey> = []
    private var pendingKeySet: Set<GameMessageKey> = []
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
        if let key = event.deduplicationKey {
            guard !recentKeySet.contains(key), !pendingKeySet.contains(key) else { return .duplicate }
            pendingKeySet.insert(key)
        }
        messages.append(event)
        return .enqueued
    }

    /// Lets a drain loop that bailed out on cancellation (see
    /// `PlayerController.processMessages()`, CODE_AUDIT.md §3.4) decide whether it needs to
    /// hand off to a fresh Task to avoid stranding whatever is still queued.
    var hasQueuedMessages: Bool {
        !messages.isEmpty
    }

    func next() -> GameMessageEvent? {
        guard !isCancelled, !processing, !messages.isEmpty else { return nil }
        processing = true
        let event = messages.removeFirst()
        currentKey = event.deduplicationKey
        currentEvent = event
        return event
    }

    func processed(success: Bool) {
        if let currentKey {
            pendingKeySet.remove(currentKey)
            if success {
                remember(currentKey)
            }
        }
        currentKey = nil
        currentEvent = nil
        processing = false
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
        if let currentEvent {
            messages.insert(currentEvent, at: 0)
        }
        if let currentKey {
            pendingKeySet.remove(currentKey)
        }
        currentKey = nil
        currentEvent = nil
        processing = false
    }

    func cancelAll() {
        messages.removeAll()
        processing = false
        isCancelled = true
        recentKeys.removeAll()
        recentKeySet.removeAll()
        pendingKeySet.removeAll()
        currentKey = nil
        currentEvent = nil
    }

    func reset() {
        messages.removeAll()
        processing = false
        isCancelled = false
        recentKeys.removeAll()
        recentKeySet.removeAll()
        pendingKeySet.removeAll()
        currentKey = nil
        currentEvent = nil
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
            Logger.networking.error("GameNetworkModel: Failed to decode inbound message: \(error.localizedDescription, privacy: .public)")
        }
        return nil
    }

    func encodeData() -> Data? {
        try? Self.outboundEncoder.encode(self)
    }
}
