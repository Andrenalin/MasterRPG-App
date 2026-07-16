// @copyright André Trettin

import AdventureRPG
import AudioRPG
import CharacterRPG
import CoreRPG
import DiceRPG
import Foundation
import MapRPG
import PdfRPG
import PhotoRPG
import SpaceRPG
import TableRPG
import WeatherRPG

extension GameRoot {
    @MainActor
    static var preview: GameRoot {
        previewFixture()
    }

    @MainActor
    static func previewFixture(
        game: GameConfigModel = .master,
        statistics: GameStatisticsSummary = GameStatisticsPreviewController().summary(
            referenceDate: GamePreviewData.referenceDate,
            calendar: GamePreviewData.calendar
        )
    ) -> GameRoot {
        let root = GameRoot(
            adventureRoot: .preview,
            audioRoot: .preview,
            diceRoot: .preview,
            mapRoot: .preview,
            pdfRoot: .preview,
            photoRoot: .preview,
            spaceRoot: .preview,
            tableRoot: .preview,
            characterRoot: .preview,
            weatherRoot: .preview
        )
        root.gameModel.applyPreviewFixture(game: game)
        root.statisticsModel.summary = statistics
        return root
    }

    @MainActor
    static func preview(_ game: GameConfigModel) -> GameRoot {
        previewFixture(game: game)
    }
}

extension MasterController {
    @MainActor
    static var preview: MasterController {
        .init(root: .previewFixture(), asProxy: false)
    }
}

extension PlayerController {
    @MainActor
    static var preview: PlayerController {
        .init(root: .previewFixture(game: .player), asGameMaster: false)
    }
}

extension LogGameController {
    @MainActor
    static var preview: LogGameController {
        LogGameController(gameModel: .previewFixture())
    }
}

extension GameRootModel {
    @MainActor
    static var preview: GameRootModel {
        previewFixture()
    }

    @MainActor
    static func previewFixture(game: GameConfigModel = .master) -> GameRootModel {
        let model = GameRootModel()
        model.applyPreviewFixture(game: game)
        return model
    }

    @MainActor
    fileprivate func applyPreviewFixture(game: GameConfigModel) {
        gameConfig = game
        gameRoster = game.isMaster ? .master : .player
        gameControl = .master
        selectedAdventure = GamePreviewData.adventureID
        selectedCharacter = GamePreviewData.characterID
        selectedGameMaster = GamePreviewData.masterID
        startGameTime = GamePreviewData.referenceDate.addingTimeInterval(-5_400)
        logs = LogGameModel.previewFixtures.map(\.id)
        logData = Dictionary(uniqueKeysWithValues: LogGameModel.previewFixtures.map { ($0.id, $0) })
        metaDataAttachments = [NetworkModules.map: GamePreviewData.mapID]
    }
}

extension GameStatisticsModel {
    @MainActor
    static func previewFixture() -> GameStatisticsModel {
        let suiteName = "GameRPG.GameStatistics.Preview"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        let model = GameStatisticsModel(defaults: defaults)
        model.summary = GameStatisticsPreviewController().summary(
            referenceDate: GamePreviewData.referenceDate,
            calendar: GamePreviewData.calendar
        )
        return model
    }
}

extension GameConfigModel {
    static let masterId = GamePreviewData.masterID
    static let playerId = GamePreviewData.playerID
    static let playerId2 = GamePreviewData.secondPlayerID

    static let player = GameConfigModel(
        id: playerId,
        state: .started,
        master: MasterGameModel(
            id: masterId,
            type: .master,
            name: "Morgan",
            adventureId: GamePreviewData.adventureID,
            adventureTitle: "The Shattered Crown"
        )
    )

    static let master = GameConfigModel(
        id: masterId,
        state: .started,
        master: MasterGameModel(
            id: masterId,
            type: .master,
            name: "Morgan",
            adventureId: GamePreviewData.adventureID,
            adventureTitle: "The Shattered Crown"
        )
    )
}

extension GameRosterModel {
    static let player = GameRosterModel(
        players: [
            PlayerGameModel(
                id: GameConfigModel.playerId,
                type: .player,
                name: "Aria",
                characterId: GamePreviewData.characterID
            )
        ]
    )

    static let master = GameRosterModel(
        players: [
            PlayerGameModel(
                id: GameConfigModel.playerId,
                type: .player,
                name: "Aria",
                characterId: GamePreviewData.characterID
            ),
            PlayerGameModel(
                id: GameConfigModel.playerId2,
                type: .player,
                name: "Borin",
                characterId: GamePreviewData.secondCharacterID
            )
        ]
    )
}

extension GameControlModel {
    static let master = GameControlModel(controls: [.previewPlayer1, .previewPlayer2])
}

extension SharingControlModel {
    static let previewPlayer1 = SharingControlModel(
        id: GameConfigModel.playerId,
        name: "Aria",
        show: true
    )
    static let previewPlayer2 = SharingControlModel(
        id: GameConfigModel.playerId2,
        name: "Borin",
        show: false
    )
}

extension LogGameModel {
    @MainActor
    static var preview: LogGameModel {
        previewFixtures[0]
    }

    @MainActor
    static var preview2: LogGameModel {
        previewFixtures[1]
    }

    @MainActor
    static var preview3: LogGameModel {
        previewFixtures[2]
    }

    @MainActor
    static var previewFixtures: [LogGameModel] {
        let photo = LogGameModel(
            id: 0,
            type: .store,
            subType: .show,
            module: .photo,
            itemId: GamePreviewData.photoID
        )
        photo.players = [GameConfigModel.playerId, GameConfigModel.playerId2]

        let map = LogGameModel(
            id: 1,
            type: .store,
            subType: .show,
            module: .map,
            itemId: GamePreviewData.mapID
        )
        map.players = [GameConfigModel.playerId]

        let hiddenMap = LogGameModel(
            id: 2,
            type: .store,
            subType: .show,
            module: .map,
            itemId: GamePreviewData.hiddenMapID
        )
        hiddenMap.players = []
        return [photo, map, hiddenMap]
    }
}

enum GamePreviewData {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }()
    static let referenceDate = Date(timeIntervalSince1970: 1_767_225_600)
    static let masterID = identifier(0x11)
    static let playerID = identifier(0x12)
    static let secondPlayerID = identifier(0x13)
    static let adventureID = identifier(0x21)
    static let characterID = identifier(0x31)
    static let secondCharacterID = identifier(0x32)
    static let mapID = identifier(0x41)
    static let hiddenMapID = identifier(0x42)
    static let photoID = identifier(0x51)
    static let searchItemID = identifier(0x61)
    static let searchEntryID = identifier(0x62)
    static let secondSearchItemID = identifier(0x63)
    static let secondSearchEntryID = identifier(0x64)

    private static func identifier(_ finalByte: UInt8) -> UUID {
        UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, finalByte))
    }
}
