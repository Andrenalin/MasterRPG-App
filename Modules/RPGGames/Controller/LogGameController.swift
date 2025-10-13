// @copyright André Trettin

import AndrenalinKit
import Foundation
import RPGPhotos
import RPGMaps
import RPGTables
import RPGAdventures
import RPGDie
import RPGWeathers
import RPGAudios
import RPGPdfs
import RPGSpaces

struct LogGameController: Sendable {
    weak var root: GameRoot?
    
    let gameModel: GameModel
    
    @MainActor
    var logModels: [LogGameModel] {
        gameModel.logs.compactMap { gameModel.logData[$0] }
    }
    
    @MainActor
    var players: [PlayerScreenModel] {
        gameModel.gameConfig.players.map {
            PlayerScreenModel(id: $0.id, name: $0.name, data: gameModel.playerScreens[$0.id])
        }.sorted { $0.name < $1.name }
    }
    
    @MainActor
    var maxPlayers: Int {
        gameModel.gameConfig.players.count
    }
    
    @MainActor
    var attachments: [AttachmentMetadata] {
        gameModel.metaDataAttachments.map {
            AttachmentMetadata(id: $0.key.token, itemId: name(for: $0.key, itemId: $0.value))
        }
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
        players.map { player -> String in
            guard let data = gameModel.gameConfig.players.first(where: { $0.id == player }) else { return "Unknown Player" }
            return data.name
        }.joined(separator: ", ")
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
