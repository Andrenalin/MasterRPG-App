// @copyright André Trettin

import RPGAdventures
import AndrenalinKit
import RPGDie
import Foundation
import RPGMaps
import PhotoRPG
import RPGTables
import RPGAudios
import RPGPdfs
import SpaceRPG
import RPGValues
import RPGWeathers

extension GameRoot {
    @MainActor
    static let preview = GameRoot(adventureRoot: .preview, audioRoot: .preview, diceRoot: .preview, mapRoot: .preview, pdfRoot: .preview, photoRoot: .preview, spaceRoot: .preview, tableRoot: .preview, valueRoot: .preview, weatherRoot: .preview)

    @MainActor
    static func preview(_ game: GameConfigModel) -> GameRoot {
        let root = GameRoot(adventureRoot: .preview, audioRoot: .preview, diceRoot: .preview, mapRoot: .preview, pdfRoot: .preview, photoRoot: .preview, spaceRoot: .preview, tableRoot: .preview, valueRoot: .preview, weatherRoot: .preview)
        root.gameModel.gameConfig = game
        root.gameModel.selectedCharacter = game.id
        root.gameModel.selectedGameMaster = game.id
        return root
    }
}

extension MasterController {
    @MainActor
    static let preview: MasterController = .init(root: .preview, asProxy: false)
}

extension PlayerController {
    @MainActor
    static let preview: PlayerController = .init(root: .preview, asGameMaster: false)
}

extension LogGameController {
    @MainActor
    static let preview = LogGameController(gameModel: .preview)
}

extension GameModel {
    @MainActor static let preview: GameModel = {
        let model = GameModel()
        model.gameConfig = .master
        model.logs = [0, 1, 2, 3, 4, 5, 6, 7, 8]
        model.logData = [0: .preview, 1: .preview2, 2: .preview3, 3: .preview, 4: .preview2, 5: .preview3, 6: .preview, 7: .preview2, 8: .preview3]
        model.metaDataAttachments = [NetworkModules.map: UUID()]
        return model
    }()
}

extension GameConfigModel {
    static let masterId: UUID = UUID()
    static let playerId: UUID = UUID()
    static let playerId2: UUID = UUID()
    
    static let player = GameConfigModel(id: playerId, state: .started, master: MasterGameModel(id: masterId, type: .master, name: "Master", adventureId: UUID(uuidString: "9E5F5A2D-EC03-4CF2-91F2-A64E820658CD")!, adventureTitle: "Adventure Testing", characterId: UUID()), players: [PlayerGameModel(id: playerId, type: .player, name: "Player", characterId: UUID(uuidString: "21EF7536-956B-4746-A731-FF15D7FE5850")!)], controls: [])

    static let master = GameConfigModel(
        id: masterId, state: .started,
        master: MasterGameModel(id: masterId, type: .master, name: "Master", adventureId: UUID(uuidString: "9E5F5A2D-EC03-4CF2-91F2-A64E820658CD")!, adventureTitle: "Adventure Testing", characterId: UUID()),
        players: [
            PlayerGameModel(id: playerId, type: .player, name: "Player", characterId: UUID(uuidString: "21EF7536-956B-4746-A731-FF15D7FE5850")!),
            PlayerGameModel(id: playerId2, type: .player, name: "Player2", characterId: UUID())
        ], controls: [.previewPlayer1, .previewPlayer2])
}

extension SharingControlModel {
    static let previewPlayer1: SharingControlModel = SharingControlModel(id: GameConfigModel.playerId, name: "Player", show: true)
    static let previewPlayer2: SharingControlModel = SharingControlModel(id: GameConfigModel.playerId2, name: "Player2", show: false)
}

extension LogGameModel {
    @MainActor
    static let preview: LogGameModel = {
        let model = LogGameModel(id: 0, type: .store, subType: .show, module: .photo, itemId: UUID())
        model.players = [GameConfigModel.player.id, GameConfigModel.empty.id]
        return model
    }()
    
    @MainActor
    static let preview2: LogGameModel = {
        let model = LogGameModel(id: 1, type: .store, subType: .show, module: .map, itemId: UUID())
        model.players = [GameConfigModel.player.id]
        return model
    }()
    
    @MainActor
    static let preview3: LogGameModel = {
        let model = LogGameModel(id: 2, type: .store, subType: .show, module: .map, itemId: UUID())
        model.players = []
        return model
    }()
}
