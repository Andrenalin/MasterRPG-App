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
import SpaceRPG

struct LogGameController: Sendable {
    weak var root: GameRoot?
    
    let gameModel: GameRootModel

    static var noPlayersText: String {
        String(localized: "No Players", bundle: .module).localizedString
    }
    
    @MainActor
    var logModels: [LogGameModel] {
        gameModel.logs.compactMap { gameModel.logData[$0] }
    }

    @MainActor
    var logRows: [LogMessageRowModel] {
        let maxPlayers = gameModel.gameRoster.players.count
        let playerNamesById = Dictionary(uniqueKeysWithValues: gameModel.gameRoster.players.map { ($0.id, $0.name) })

        return gameModel.logs.reversed().compactMap { counter in
            guard let model = gameModel.logData[counter] else { return nil }
            return LogMessageRowModel(
                id: model.id,
                title: title(for: model),
                playerNames: logPlayerNames(for: model.players, namesById: playerNamesById),
                deliveryState: deliveryState(for: model, maxPlayers: maxPlayers)
            )
        }
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
        let log = LogGameModel(id: counter, type: type, subType: subType, module: module, itemId: itemId)
        gameModel.logs.append(counter)
        gameModel.logData[counter] = log
    }
    
    @MainActor
    func updateMessage(counter: Int, player: UUID) {
        gameModel.logData[counter]?.players.append(player)
    }

    @MainActor
    func updateScreen(counter: Int, player: UUID, data: Data?) {
        guard let data else { return }
        gameModel.playerScreens[player] = data
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
    private func deliveryState(for model: LogGameModel, maxPlayers: Int) -> LogMessageDeliveryState {
        guard model.type == .reveal else { return .notTracked }
        if maxPlayers > 0 && model.players.isEmpty {
            return .missingPlayers
        }
        if model.players.count < maxPlayers {
            return .partialPlayers
        }
        return .allPlayers
    }
}

struct LogMessageRowModel: Identifiable, Equatable, Sendable {
    let id: Int
    let title: String
    let playerNames: String
    let deliveryState: LogMessageDeliveryState
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
