// @copyright André Trettin

import CoreRPG
import Foundation
import CharacterRPG
import PhotoRPG
import MapRPG
import TableRPG
import AdventureRPG
import DiceRPG
import WeatherRPG
import AudioRPG
import PdfRPG
import RuleRPG
import SpaceRPG

struct LogGameController: Sendable {
    weak var root: GameRoot?
    
    let gameModel: GameRootModel

    static let maximumVisibleMessages = 25
    /// See CODE_AUDIT_Game §7.5 — bounds `gameModel.logs`/`logData`, which
    /// otherwise grow for the whole session even though only
    /// `maximumVisibleMessages` are ever shown.
    static let maximumRetainedMessages = 300

    static var noPlayersText: String {
        String(localized: "No Players", bundle: .module).localizedString
    }
    
    /// Test affordance — production code reads `logRows` instead.
    /// See CODE_AUDIT_Game §9.22.
    @MainActor
    var logModels: [LogGameModel] {
        gameModel.logs.compactMap { gameModel.logData[$0] }
    }

    @MainActor
    var logRows: [LogMessageRowModel] {
        // `uniqueKeysWithValues` traps on a duplicate id; roster/recipient data
        // ultimately originates off-device, so last-wins here instead of
        // crashing the whole log view. See CODE_AUDIT_Game §5.5.
        let playerNamesById = Dictionary(gameModel.gameRoster.players.map { ($0.id, $0.name) }, uniquingKeysWith: { _, new in new })

        var rows: [LogMessageRowModel] = []
        for counter in gameModel.logs.reversed() {
            guard let model = gameModel.logData[counter] else { continue }
            let snapshotNamesById = Dictionary(model.expectedRecipients.map { ($0.id, $0.name) }, uniquingKeysWith: { _, new in new })
            let namesById = playerNamesById.merging(snapshotNamesById) { _, snapshotName in snapshotName }
            rows.append(LogMessageRowModel(
                id: model.id,
                title: title(for: model),
                playerNames: logPlayerNames(for: model.players, namesById: namesById),
                deliveryState: deliveryState(for: model),
                playerStatuses: playerStatuses(for: model),
                sharePlayTransport: model.sharePlayTransport
            ))
            if rows.count == Self.maximumVisibleMessages {
                break
            }
        }
        return rows
    }
    
    /// Test affordance. See CODE_AUDIT_Game §9.22.
    @MainActor
    var maxPlayers: Int {
        gameModel.gameRoster.players.count
    }
    
    @MainActor
    var attachments: [AttachmentMetadata] {
        gameModel.metaDataAttachments.map {
            AttachmentMetadata(id: $0.key.token, itemId: name(for: $0.key, itemId: $0.value))
        }.sorted { $0.id < $1.id }
    }
    
    @MainActor
    func addMessage(counter: Int, type: RPGMessageType, subType: RPGMessageActionType, module: NetworkModules, itemId: UUID) {
        let sessionID = currentSessionID ?? GameDeliveryMessageID.legacySessionID
        addMessage(
            messageID: GameDeliveryMessageID(sessionID: sessionID, counter: counter),
            type: type,
            subType: subType,
            module: module,
            itemId: itemId
        )
    }

    /// Starts a fresh delivery namespace. Existing rows belong to the previous
    /// game and are removed so a restarted counter can never overwrite or
    /// complete them.
    @MainActor
    func beginDeliverySession(_ sessionID: UUID) {
        guard currentSessionID != sessionID else { return }
        gameModel.logs.removeAll()
        gameModel.logData.removeAll()
    }

    /// Records a master send together with the exact recipients that can
    /// process it at send time. The snapshot is never recomputed from the live
    /// roster.
    @MainActor
    func addMessage(
        messageID: GameDeliveryMessageID,
        type: RPGMessageType,
        subType: RPGMessageActionType,
        module: NetworkModules,
        itemId: UUID,
        targetID: UUID? = nil,
        tracksDelivery: Bool? = nil
    ) {
        beginDeliverySession(messageID.sessionID)

        let log = LogGameModel(
            id: messageID.counter,
            type: type,
            subType: subType,
            module: module,
            itemId: itemId,
            messageID: messageID,
            expectedRecipients: recipientSnapshot(targetID: targetID),
            tracksDelivery: tracksDelivery
        )

        if gameModel.logData[messageID.counter] == nil {
            gameModel.logs.append(messageID.counter)
            // Unbounded before this — a long session produced thousands of
            // entries even though the UI only ever renders `maximumVisibleMessages`.
            // Same bounded-FIFO treatment as `MasterControllerModel.deliveryMessagesByWireID`.
            // See CODE_AUDIT_Game §7.5.
            while gameModel.logs.count > Self.maximumRetainedMessages {
                gameModel.logData[gameModel.logs.removeFirst()] = nil
            }
        }
        gameModel.logData[messageID.counter] = log
    }
    
    /// Test affordance — production code calls `updateMessage(messageID:player:)`
    /// directly, already having the full `GameDeliveryMessageID`.
    /// See CODE_AUDIT_Game §9.22.
    @MainActor
    func updateMessage(counter: Int, player: UUID) {
        guard let messageID = gameModel.logData[counter]?.messageID else { return }
        updateMessage(messageID: messageID, player: player)
    }

    /// Applies an acknowledgement only to its exact session-qualified send.
    /// Duplicate, stale, unexpected, and cross-session acknowledgements are
    /// ignored.
    @MainActor
    @discardableResult
    func updateMessage(messageID: GameDeliveryMessageID, player: UUID) -> Bool {
        guard let log = gameModel.logData[messageID.counter],
              log.messageID == messageID
        else { return false }
        return log.acknowledge(playerID: player)
    }

    /// Exact logical recipients captured with the same policy as a delivery
    /// row. Peer-origin file presentations use this snapshot for correlating
    /// their later acknowledgements even though they do not create a master
    /// message-log row of their own.
    @MainActor
    func recipientIDs(targetID: UUID? = nil) -> Set<UUID> {
        Set(recipientSnapshot(targetID: targetID).map(\.id))
    }

    /// Test affordance. See CODE_AUDIT_Game §9.22.
    @MainActor
    func playerNames(for players: [UUID]) -> String {
        let playerNamesById = Dictionary(gameModel.gameRoster.players.map { ($0.id, $0.name) }, uniquingKeysWith: { _, new in new })
        return namedPlayers(for: players, namesById: playerNamesById)
    }
    
    @MainActor
    func name(for module: NetworkModules, itemId: UUID) -> String {
        switch module {
        case .none:
            return itemId.uuidString
        case .photo:
            return root?.photoRoot.itemControllable.nameSync(itemId: itemId) ?? itemId.uuidString
        case .rule:
            return root?.ruleRoot?.itemControllable.nameSync(itemId: itemId) ?? itemId.uuidString
        case .map:
            return root?.mapRoot.itemControllable.nameSync(itemId: itemId) ?? itemId.uuidString
        case .table:
            return root?.tableRoot.itemControllable.nameSync(itemId: itemId) ?? itemId.uuidString
        case .adventure:
            return root?.adventureRoot.itemControllable.nameSync(itemId: itemId) ?? itemId.uuidString
        case .dice:
            return root?.diceRoot.itemControllable.nameSync(itemId: itemId) ?? itemId.uuidString
        case .weather:
            return root?.weatherRoot.itemControllable.nameSync(itemId: itemId) ?? itemId.uuidString
        case .game:
            return itemId.uuidString
        case .value:
            return root?.characterRoot.itemControllable.nameSync(itemId: itemId) ?? itemId.uuidString
        case .audio:
            return root?.audioRoot.itemControllable.nameSync(itemId: itemId) ?? itemId.uuidString
        case .pdf:
            return root?.pdfRoot.itemControllable.nameSync(itemId: itemId) ?? itemId.uuidString
        case .space:
            return root?.spaceRoot.itemControllable.nameSync(itemId: itemId) ?? itemId.uuidString
        case .setting:
            return itemId.uuidString
        case .editor:
            return itemId.uuidString
        case .generator, .search:
            return itemId.uuidString
        @unknown default:
            return itemId.uuidString
        }
    }

    @MainActor
    private func title(for model: LogGameModel) -> String {
        "\(model.id): \(model.type.debugDescription) -  \(model.subType.debugDescription) - \(model.module.token) \(name(for: model.module, itemId: model.itemId))"
    }

    private func logPlayerNames(for players: [UUID], namesById: [UUID: String]) -> String {
        guard !players.isEmpty else { return Self.noPlayersText }
        return namedPlayers(for: players, namesById: namesById)
    }

    private func namedPlayers(for players: [UUID], namesById: [UUID: String]) -> String {
        players.map { namesById[$0] ?? "Unknown Player" }.joined(separator: ", ")
    }

    @MainActor
    private var currentSessionID: UUID? {
        for counter in gameModel.logs.reversed() {
            if let messageID = gameModel.logData[counter]?.messageID {
                return messageID.sessionID
            }
        }
        return nil
    }

    @MainActor
    private func recipientSnapshot(targetID: UUID?) -> [LogMessageRecipient] {
        let controls = gameModel.gameControl.controls
        // `controls` is fed by the master's broadcast state — on a
        // proxy-hosting player device it came straight off the wire, so a
        // malformed/hostile master must not crash every relaying player.
        // See CODE_AUDIT_Game §5.5.
        let controlsByID = Dictionary(controls.map { ($0.id, $0.show) }, uniquingKeysWith: { _, new in new })
        var seen = Set<UUID>()

        return gameModel.gameRoster.players.compactMap { player in
            guard seen.insert(player.id).inserted else { return nil }
            if let targetID, player.id != targetID { return nil }

            let receivesMasterMessages = switch player.type {
            case .observer, .proxy:
                true
            default:
                controls.isEmpty || controlsByID[player.id] == true
            }
            guard receivesMasterMessages else { return nil }
            return LogMessageRecipient(id: player.id, name: player.name)
        }
    }

    @MainActor
    private func playerStatuses(for model: LogGameModel) -> [LogMessagePlayerStatus] {
        model.expectedRecipients
            .map {
                LogMessagePlayerStatus(
                    id: $0.id,
                    name: $0.name,
                    received: model.hasAcknowledgement(from: $0.id)
                )
            }
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    @MainActor
    private func deliveryState(for model: LogGameModel) -> LogMessageDeliveryState {
        guard model.tracksDelivery else { return .notTracked }
        let receivedCount = model.expectedRecipients.reduce(into: 0) { count, recipient in
            if model.hasAcknowledgement(from: recipient.id) {
                count += 1
            }
        }
        if !model.expectedRecipients.isEmpty && receivedCount == 0 {
            return .missingPlayers
        }
        if receivedCount < model.expectedRecipients.count {
            return .partialPlayers
        }
        return .allPlayers
    }
}

struct LogMessageRowModel: Identifiable, Equatable, Sendable {
    init(
        id: Int,
        title: String,
        playerNames: String,
        deliveryState: LogMessageDeliveryState,
        playerStatuses: [LogMessagePlayerStatus] = [],
        sharePlayTransport: SharePlayTransportLog = SharePlayTransportLog()
    ) {
        self.id = id
        self.title = title
        self.playerNames = playerNames
        self.deliveryState = deliveryState
        self.playerStatuses = playerStatuses
        self.sharePlayTransport = sharePlayTransport
    }

    let id: Int
    let title: String
    let playerNames: String
    let deliveryState: LogMessageDeliveryState
    let playerStatuses: [LogMessagePlayerStatus]
    let sharePlayTransport: SharePlayTransportLog
}

struct LogMessagePlayerStatus: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    let received: Bool
}

enum LogMessageDeliveryState: Equatable, Sendable {
    case notTracked
    case missingPlayers
    case partialPlayers
    case allPlayers
}

struct AttachmentMetadata: Identifiable {
    let id: String
    let itemId: String
}
