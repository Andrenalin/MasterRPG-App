// @copyright André Trettin

import CoreRPG
import Foundation
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

    static var noPlayersText: String {
        String(localized: "No Players", bundle: .module).localizedString
    }
    
    @MainActor
    var logModels: [LogGameModel] {
        gameModel.logs.compactMap { gameModel.logData[$0] }
    }

    @MainActor
    var logRows: [LogMessageRowModel] {
        let playerNamesById = Dictionary(uniqueKeysWithValues: gameModel.gameRoster.players.map { ($0.id, $0.name) })

        var rows: [LogMessageRowModel] = []
        for counter in gameModel.logs.reversed() {
            guard let model = gameModel.logData[counter] else { continue }
            let snapshotNamesById = Dictionary(uniqueKeysWithValues: model.expectedRecipients.map { ($0.id, $0.name) })
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
    
    @MainActor
    var players: [PlayerScreenModel] {
        gameModel.gameRoster.players.map {
            PlayerScreenModel(id: $0.id, name: $0.name, data: gameModel.playerScreens[$0.id])
        }.sorted { $0.name < $1.name }
    }

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
        }
        gameModel.logData[messageID.counter] = log
    }
    
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

    @MainActor
    func updateScreen(counter: Int, player: UUID, data: Data?) {
        guard let data else { return }
        gameModel.playerScreens[player] = data
    }

    /// Exact logical recipients captured with the same policy as a delivery
    /// row. Peer-origin file presentations use this snapshot for correlating
    /// their later acknowledgements even though they do not create a master
    /// message-log row of their own.
    @MainActor
    func recipientIDs(targetID: UUID? = nil) -> Set<UUID> {
        Set(recipientSnapshot(targetID: targetID).map(\.id))
    }

    @MainActor
    func playerNames(for players: [UUID]) -> String {
        let playerNamesById = Dictionary(uniqueKeysWithValues: gameModel.gameRoster.players.map { ($0.id, $0.name) })
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
            return root?.photoRoot.itemControllable.nameSync(itemId: itemId) ?? itemId.uuidString
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
            fatalError()
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
        let controlsByID = Dictionary(uniqueKeysWithValues: controls.map { ($0.id, $0.show) })
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

struct PlayerScreenModel: Identifiable {
    let id: UUID
    let name: String
    let data: Data?
}
