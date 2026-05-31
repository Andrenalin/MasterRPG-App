// @copyright André Trettin

import AdventureRPG
import CoreRPG
import Combine
import DiceRPG
import Foundation
import GroupActivities
import AudioRPG
import MapRPG
import PdfRPG
import PhotoRPG
import SpaceRPG
import TableRPG
import CharacterRPG
import SwiftUI
import WeatherRPG


@MainActor @Observable
final class GameModel: Sendable {
    var gameConfig: GameConfigModel = .empty
    var gameRoster: GameRosterModel = .empty

    var startGameTime = Date()

    var selectedCharacter: UUID?
    var selectedGameMaster: UUID?
    public var selectedAdventure: UUID?

    var playerGameStarted: Bool = false

    var logData: [Int: LogGameModel] = [:]
    var logs: [Int] = []
    var playerScreens: [UUID: Data] = [:]
    var attachments: [NetworkModules: GroupSessionJournal.Attachment] = [:]
    var metaDataAttachments: [NetworkModules: UUID] = [:]

    var masterController: MasterController?
    var playerController: PlayerController?

    #if os(visionOS)
    var gameTableModel: GameTableModel?
    var shareState = GameShareStateModel()
    #endif

    func add(playerId: UUID, playerModel: PlayerGameModel, sharingModel: SharingControlModel) -> Bool {
        if let index = gameRoster.players.firstIndex(where: { $0.id == playerId }) {
            gameRoster.players[index] = playerModel
            var model = sharingModel
            model.show = gameRoster.controls[index].show
            gameRoster.controls[index] = model
            return false
        } else {
            gameRoster.players.append(playerModel)
            gameRoster.controls.append(sharingModel)
            return true
        }
    }

    func add(playerId: UUID, sharingModel: SharingControlModel) {
        if let index = gameRoster.players.firstIndex(where: { $0.id == playerId }) {
            gameRoster.controls[index] = sharingModel
        } else {
            gameRoster.controls.append(sharingModel)
        }
    }

    func remove(playerId: UUID) -> Bool {
        guard let index = gameRoster.players.firstIndex(where: { $0.id == playerId }) else { return false }
        gameRoster.players.remove(at: index)
        gameRoster.controls.remove(at: index)
        return true
    }

    func reset(gameConfig: GameConfigModel, gameRoster: GameRosterModel = .empty) {
        self.gameConfig = gameConfig
        self.gameRoster = gameRoster
    }

    func reset(controls: [SharingControlModel]) {
        gameRoster.controls = controls
    }

    func reset(master: MasterGameModel) {
        gameConfig.master = master
    }

    func reset(playerId: UUID, player: PlayerGameModel, players: [PlayerGameModel]) {
        var updatedPlayers = players
        if !updatedPlayers.contains(where: { $0.id == playerId }) {
            updatedPlayers.append(player)
        }
        gameRoster.players = updatedPlayers
    }

    func reset(features: GameFeatureModel) {
        gameRoster.features = features
    }

    var gameType: GameType { gameConfig.type(in: gameRoster) }
    var gameName: String { gameConfig.name(in: gameRoster) }
    var gamePlayer: PlayerGameModel { gameConfig.player(in: gameRoster) }
}

public final class GameRoot: @unchecked Sendable {
    let adventureRoot: AdventureRootModel
    let audioRoot: AudioRootModel
    let diceRoot: DiceRootModel
    let mapRoot: MapRootModel
    var networkStore: NetworkController
    var networkProxyStore: NetworkProxyController
    let pdfRoot: PdfRootModel
    let photoRoot: PhotoRootModel
    let spaceRoot: SpaceRootModel
    let tableRoot: TableRootModel
    let characterRoot: CharacterRootModel
    let weatherRoot: WeatherRootModel

    let gameModel: GameModel

    @MainActor
    public init(adventureRoot: AdventureRootModel, audioRoot: AudioRootModel, diceRoot: DiceRootModel, mapRoot: MapRootModel, pdfRoot: PdfRootModel, photoRoot: PhotoRootModel, spaceRoot: SpaceRootModel, tableRoot: TableRootModel, characterRoot: CharacterRootModel, weatherRoot: WeatherRootModel) {
        self.adventureRoot = adventureRoot
        self.audioRoot = audioRoot
        self.diceRoot = diceRoot
        self.mapRoot = mapRoot
        self.pdfRoot = pdfRoot
        self.photoRoot = photoRoot
        self.spaceRoot = spaceRoot
        self.tableRoot = tableRoot
        self.characterRoot = characterRoot
        self.weatherRoot = weatherRoot
        
        self.networkStore = NetworkController(name: "Init")
        self.networkProxyStore = NetworkProxyController(name: "Proxy")
        
        self.gameModel = GameModel()
        
        _viewController = ViewController(root: self)
        _logGameController = LogGameController(root: self, gameModel: gameModel)
    }

    private(set) var _viewController: ViewController?
    public var viewController: ViewController {
        _viewController.unsafelyUnwrapped
    }
    
    private(set) var _logGameController: LogGameController?
    var logGameController: LogGameController {
        _logGameController.unsafelyUnwrapped
    }
    
    @MainActor lazy var searchController: SearchGlobalController = {
        SearchGlobalController(root: self)
    }()

    @MainActor public lazy var networkActions: NetworkActions = NetworkActions { @MainActor [weak self] idType in
        guard let store = self?.gameModel.masterController else { return }
        Task {
            await store.show(for: idType)
        }
    } send: { @MainActor [weak self] update in
        let masterStore = self?.gameModel.masterController
        let playerStore = self?.gameModel.playerController
        Task {
            if let masterStore {
                await masterStore.send(updated: update)
            } else {
                await playerStore?.send(updated: update)
            }
        }
    } game: { @MainActor [weak self] message, actionType, playerId in
        let masterStore = self?.gameModel.masterController
        let playerStore = self?.gameModel.playerController
        Task {
            if let masterStore {
                await masterStore.game(message: message, actionType: actionType, playerId: playerId)
            } else {
                await playerStore?.game(message: message, actionType: actionType)
            }
        }
    }

    @MainActor public lazy var sharingControlActions: SharingControlActions = SharingControlActions { [weak self] in
        self?.gameModel.gameRoster.controls ?? []
    } update: { [weak self] newControls in
        if self?.gameModel.gameRoster.controls != newControls {
            self?.gameModel.gameRoster.controls = newControls
        }
        Task {
            await self?.gameModel.masterController?.resetPlayers()
        }
    }

    @MainActor public lazy var sharingFeatureActions: SharingFeatureActions = SharingFeatureActions { [weak self] in
        self?.gameModel.gameRoster.features ?? GameFeatureModel()
    }
    
    @MainActor
    var characterName: String {
        if let selectedCharacter = gameModel.selectedCharacter {
            return characterRoot.linkControllable.name(for: selectedCharacter)
        } else {
            return "Unknown"
        }
    }

    @MainActor
    var gameMasterName: String {
        String(localized: "GameMaster", bundle: .module).localizedString
    }
}

// MARK: - Master / Player selection views and handling

extension GameRoot {
    @MainActor
    func resetSelectedAdventure(uuidString: String) {
        guard let uuid = UUID(uuidString: uuidString) else {
            if gameModel.selectedAdventure != nil {
                gameModel.selectedAdventure = nil
            }
            return
        }
        gameModel.selectedAdventure <=> uuid
    }

    @MainActor
    func resetSelectedCharacter(uuidString: String) {
        guard let uuid = UUID(uuidString: uuidString) else {
            if gameModel.selectedCharacter != nil {
                gameModel.selectedCharacter = nil
            }
            return
        }
        gameModel.selectedCharacter <=> uuid
    }

    @MainActor
    func resetSelectedGameMaster(uuidString: String) {
        guard let uuid = UUID(uuidString: uuidString) else {
            if gameModel.selectedGameMaster != nil {
                gameModel.selectedGameMaster = nil
            }
            return
        }
        gameModel.selectedGameMaster <=> uuid
    }
}

// MARK: - Master Control Game

extension GameRoot {
    @MainActor
    func startMaster() async {
        guard gameModel.gameConfig.state == .stopped else {
            await stopGame()
            return
        }
        guard let id = gameModel.selectedAdventure else {
            return
        }
        
        let masterGameModel = MasterGameModel(id: UUID(), type: .master, name: gameMasterName, adventureId: id, adventureTitle: adventureRoot.networkTitle(for: id))
        var newConfig = gameModel.gameConfig
        newConfig.id = masterGameModel.id
        newConfig.master = masterGameModel
        gameModel.gameConfig = newConfig
        gameModel.startGameTime = Date.now
        #if os(visionOS)
        gameModel.shareState.isMaster = true
        #endif
        
        networkStore.resetName(name: gameMasterName)
        networkProxyStore.resetName(name: gameMasterName)
        networkStore.sharePlayStore.setup(audioCoordinator: audioRoot.audioCoordinatorPlayback)

        adventureRoot.adventureGameControllable.startGame(with: id)
        gameModel.playerController = PlayerController(root: self, asGameMaster: true)
        gameModel.masterController = MasterController(root: self, asProxy: false)

        gameModel.gameConfig.state = .started
        adventureRoot.startGame()

        await gameModel.masterController?.start()
        diceRoot.diceGameControllable.setFocusDice(on: adventureRoot.adventureGameControllable.focusDice(for: gameModel.selectedAdventure!))
        
#if !os(macOS)
        UIApplication.shared.isIdleTimerDisabled = true
#endif
    }
}

// MARK: - Player Control Game

extension GameRoot {
    @MainActor
    private func name(for type: GameType) -> String {
        switch type {
        case .observer:
            return "Observer"
        case .proxy:
            return "Proxy"
        default:
            return characterName
        }
    }

    @MainActor
    func startGame(to model: BrowserDeviceModel?, mode: GameType) async {
        if (mode == .proxy || mode == .observer || mode == .demo) {
            gameModel.selectedCharacter = nil
        }
        let playerGameModel = PlayerGameModel(id: UUID(), type: mode, name: name(for: mode), characterId: gameModel.selectedCharacter)
        gameModel.gameRoster = GameRosterModel(players: [playerGameModel])
        var newConfig = gameModel.gameConfig
        newConfig.id = playerGameModel.id
        newConfig.state = .prepare
        gameModel.gameConfig = newConfig
        networkStore.resetName(name: name(for: mode))
        if mode == .player {
            networkProxyStore.resetName(name: characterName)
            networkStore.sharePlayStore.setup(audioCoordinator: audioRoot.audioCoordinatorPlayback)
        }

        adventureRoot.adventureGameControllable.resetGame()
        #if os(visionOS)
        gameModel.shareState.isMaster = (mode == .demo)
        #endif
        let player = PlayerController(root: self, asGameMaster: mode == .demo)
        gameModel.playerController = player

        if mode == .demo {
            joinGame(for: mode)

#if !os(macOS)
            UIApplication.shared.isIdleTimerDisabled = true
#endif
        } else if await player.start(to: model) {
            joinGame(for: mode)

#if !os(macOS)
            UIApplication.shared.isIdleTimerDisabled = true
#endif
        } else {
            await stopGame()
        }
    }

    @MainActor
    func joinGame(for type: GameType) {
        gameModel.startGameTime = Date.now
        gameModel.playerGameStarted = true
        var newConfig = gameModel.gameConfig
        newConfig.state = .started
        gameModel.gameConfig = newConfig
        gameModel.gameRoster.players[0].type = type
        gameModel.gameRoster.players[0].name = name(for: type)
        adventureRoot.startGame()
        if type != .observer {
            characterRoot.valueGameControllable.startGame(for: gameModel.selectedCharacter)
            diceRoot.diceGameControllable.setFocusDice(on: characterRoot.valueGameControllable.focusDice(for: gameModel.selectedCharacter ?? UUID()))
        }
    }

    // both
    @MainActor
    func stopGame() async {
        gameModel.playerGameStarted = false
        gameModel.gameConfig.state = .stopped
        gameModel.gameConfig = .empty
        await gameModel.masterController?.stop()
        gameModel.masterController = nil
        await gameModel.playerController?.stop()
        gameModel.playerController = nil
        adventureRoot.adventureGameControllable.resetGame()
        #if os(visionOS)
        gameModel.shareState = GameShareStateModel()
        #endif

#if !os(macOS)
        UIApplication.shared.isIdleTimerDisabled = false
#endif
    }

    @MainActor
    func saveGame() -> ItemModuleIds {
        adventureRoot.adventureGameControllable.saveGame()
    }
}

// MARK: - Demo

extension GameRoot {
    @MainActor
    func startDemo() async {
        await startGame(to: nil, mode: .demo)

        if let playerController = gameModel.playerController {
            Task {
                while gameModel.gameConfig.state != .stopped {
                    let photos = photoRoot.itemControllable.itemDataModel.items
                    for photo in photos {
                        try await Task.sleep(for: .seconds(3))
                        let data = await photoRoot.gameControllable.share(id: photo)
                        let gameNetworkModel = GameNetworkModel(counter: 1, proxyCounter: 0, type: .reveal, subType: .show, gameConfig: gameModel.gameConfig, data: data)
                        await playerController.receivedProcess(gameNetworkModel)
                    }
                    
                    let weathers = weatherRoot.itemControllable.itemDataModel.items
                    for weather in weathers {
                        try await Task.sleep(for: .seconds(5))
                        let data = await weatherRoot.gameControllable.share(id: weather)
                        let gameNetworkModel = GameNetworkModel(counter: 2, proxyCounter: 0, type: .reveal, subType: .show, gameConfig: gameModel.gameConfig, data: data)
                        await playerController.receivedProcess(gameNetworkModel)
                    }
                    
                    let maps = mapRoot.itemControllable.itemDataModel.items
                    for map in maps {
                        try await Task.sleep(for: .seconds(5))
                        let data = await mapRoot.gameControllable.share(id: map)
                        let gameNetworkModel = GameNetworkModel(counter: 2, proxyCounter: 0, type: .reveal, subType: .show, gameConfig: gameModel.gameConfig, data: data)
                        await playerController.receivedProcess(gameNetworkModel)
                        
                        var showMap = true
                        
                        while showMap {
                            var data = mapRoot.mapGameControllable.demoNextMap(itemId: map, restart: false)
                            if data == nil {
                                data = mapRoot.mapGameControllable.demoNextMap(itemId: map, restart: true)
                                showMap = false
                            }
                            guard let data else { break }
                            try await Task.sleep(for: .seconds(3))
                            
                            let gameNetworkModel = GameNetworkModel(counter: 2, proxyCounter: 0, type: .update, subType: .mapState, gameConfig: gameModel.gameConfig, data: data)
                            await playerController.receivedProcess(gameNetworkModel)
                        }
                    }
                }
            }
        }
    }
}


// MARK: - Search Helpers

extension GameRoot {
    @MainActor
    func rootController(for module: NetworkModules) -> ItemRootController {
        switch module {
        case .adventure:
            adventureRoot.rootController
        case .audio:
            audioRoot.rootController
        case .value:
            characterRoot.rootController
        case .dice:
            diceRoot.rootController
        case .map:
            mapRoot.rootController
        case .pdf:
            pdfRoot.rootController
        case .photo:
            photoRoot.rootController
        case .space:
            spaceRoot.rootController
        case .table:
            tableRoot.rootController
        case .weather:
            weatherRoot.rootController
        default:
            adventureRoot.rootController
        }
    }
}

// MARK: - Widget

extension GameRoot {
    @MainActor func widgetGameRunningChanged() {
        if gameModel.gameConfig.state == .started {
            let defaults = UserDefaults(suiteName: UserDefaults.appGroupString)
            defaults?.set(true, forKey: UserDefaults.DiceKeys.isGameActive)
            defaults?.set(gameModel.gameConfig.master.adventureTitle, forKey: UserDefaults.DiceKeys.currentGameName)
            diceRoot.diceGameControllable.clearAllFavoriteDice()
        } else {
            let defaults = UserDefaults(suiteName: UserDefaults.appGroupString)
            defaults?.set(false, forKey: UserDefaults.DiceKeys.isGameActive)
            defaults?.set("", forKey: UserDefaults.DiceKeys.currentGameName)
            diceRoot.diceGameControllable.clearAllFavoriteDice()
        }
    }
}
