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
        let moduleRoots = GamePreviewModuleRoots()
        let root = GameRoot(
            adventureRoot: moduleRoots.adventure,
            audioRoot: moduleRoots.audio,
            diceRoot: moduleRoots.dice,
            mapRoot: moduleRoots.map,
            pdfRoot: moduleRoots.pdf,
            photoRoot: moduleRoots.photo,
            spaceRoot: moduleRoots.space,
            tableRoot: moduleRoots.table,
            characterRoot: moduleRoots.character,
            weatherRoot: moduleRoots.weather
        )
        root.gameModel.applyPreviewFixture(game: game)
        root.statisticsModel.summary = statistics
        root.gameModel.playerController = PlayerController(
            root: root,
            asGameMaster: game.isMaster
        )
        if game.isMaster {
            root.gameModel.masterController = MasterController(root: root, asProxy: false)
        }
        BattleRoundPreviewData.apply(to: root.mapRoot)
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
        selectedAdventure = GamePreviewData.adventureId
        selectedCharacter = GamePreviewData.characterId
        selectedGameMaster = GamePreviewData.masterId
        startGameTime = GamePreviewData.referenceDate.addingTimeInterval(-5_400)
        logs = LogGameModel.previewFixtures.map(\.id)
        logData = Dictionary(uniqueKeysWithValues: LogGameModel.previewFixtures.map { ($0.id, $0) })
        metaDataAttachments = [NetworkModules.map: GamePreviewData.mapId]
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
    static let masterId = GamePreviewData.masterId
    static let playerId = GamePreviewData.playerId
    static let playerId2 = GamePreviewData.secondPlayerId

    static let player = GameConfigModel(
        id: playerId,
        state: .started,
        master: MasterGameModel(
            id: masterId,
            type: .master,
            name: "Morgan",
            adventureId: GamePreviewData.adventureId,
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
            adventureId: GamePreviewData.adventureId,
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
                characterId: GamePreviewData.characterId
            )
        ]
    )

    static let master = GameRosterModel(
        players: [
            PlayerGameModel(
                id: GameConfigModel.playerId,
                type: .player,
                name: "Aria",
                characterId: GamePreviewData.characterId
            ),
            PlayerGameModel(
                id: GameConfigModel.playerId2,
                type: .player,
                name: "Borin",
                characterId: GamePreviewData.secondCharacterId
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
    static var previewFixtures: [LogGameModel] {
        let photo = LogGameModel(
            id: 0,
            type: .store,
            subType: .show,
            module: .photo,
            itemId: GamePreviewData.photoId
        )
        photo.players = [GameConfigModel.playerId, GameConfigModel.playerId2]

        let map = LogGameModel(
            id: 1,
            type: .store,
            subType: .show,
            module: .map,
            itemId: GamePreviewData.mapId
        )
        map.players = [GameConfigModel.playerId]

        let hiddenMap = LogGameModel(
            id: 2,
            type: .store,
            subType: .show,
            module: .map,
            itemId: GamePreviewData.hiddenMapId
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
    static let masterId = identifier(0x11)
    static let playerId = identifier(0x12)
    static let secondPlayerId = identifier(0x13)
    static let adventureId = UUID(
        uuid: (0x5F, 0x6D, 0x6D, 0x52, 0x3D, 0xDB, 0x4B, 0x20,
               0x8D, 0x45, 0xDF, 0xB5, 0x43, 0x79, 0x94, 0x17)
    )
    static let characterId = UUID(
        uuid: (0x15, 0x27, 0x14, 0x0F, 0x01, 0x01, 0x46, 0xC3,
               0x91, 0x2E, 0xB0, 0x2F, 0xE0, 0xFF, 0x76, 0x96)
    )
    static let secondCharacterId = identifier(0x32)
    static let mapId = UUID(
        uuid: (0x50, 0xDF, 0xDB, 0x6F, 0xE8, 0xB1, 0x41, 0xA4,
               0xA4, 0x09, 0x91, 0x1D, 0x88, 0x81, 0x19, 0xE8)
    )
    static let hiddenMapId = UUID(
        uuid: (0xB1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1)
    )
    static let photoId = UUID(
        uuid: (0x12, 0x97, 0x55, 0x03, 0xCC, 0x29, 0x48, 0x37,
               0x80, 0x18, 0xEF, 0xF7, 0x74, 0xE9, 0x75, 0x95)
    )
    static let searchItemId = identifier(0x61)
    static let searchEntryId = identifier(0x62)
    static let secondSearchItemId = identifier(0x63)
    static let secondSearchEntryId = identifier(0x64)

    private static func identifier(_ finalByte: UInt8) -> UUID {
        UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, finalByte))
    }
}

@MainActor
private struct GamePreviewModuleRoots {
    let adventure: AdventureRootModel
    let audio: AudioRootModel
    let dice: DiceRootModel
    let map: MapRootModel
    let pdf: PdfRootModel
    let photo: PhotoRootModel
    let space: SpaceRootModel
    let table: TableRootModel
    let character: CharacterRootModel
    let weather: WeatherRootModel

    init() {
        let adventure = AdventureRootModel.previewFixture()
        guard let rootManager = adventure.rootManager,
              let audio = rootManager.audioRoot as? AudioRootModel,
              let dice = rootManager.diceRoot as? DiceRootModel,
              let map = rootManager.mapRoot as? MapRootModel,
              let pdf = rootManager.pdfRoot as? PdfRootModel,
              let photo = rootManager.photoRoot as? PhotoRootModel,
              let space = rootManager.spaceRoot as? SpaceRootModel,
              let table = rootManager.tableRoot as? TableRootModel,
              let character = rootManager.characterRoot as? CharacterRootModel,
              let weather = rootManager.weatherRoot as? WeatherRootModel else {
            preconditionFailure("Adventure preview must provide the complete module root graph")
        }
        self.adventure = adventure
        self.audio = audio
        self.dice = dice
        self.map = map
        self.pdf = pdf
        self.photo = photo
        self.space = space
        self.table = table
        self.character = character
        self.weather = weather
    }
}
