//// @copyright André Trettin
//
//import RPGAdventures
//import AndrenalinKit
//import Combine
//import RPGDie
//import Foundation
//import GroupActivities
//import RPGAudios
//import RPGMaps
//import RPGPdfs
//import RPGPhotos
//import RPGSpaces
//import RPGTables
//import RPGValues
//import SwiftUI
//import RPGWeathers
//
//
//@MainActor @Observable
//final class GameModel: Sendable {
//    var gameConfig: GameConfigModel = .empty
//    
//    var startGameTime = Date()
//    
//    var selectedCharacter: UUID?
//    var selectedGameMaster: UUID?
//    public var selectedAdventure: UUID?
//    
//    var playerGameStarted: Bool = false
//    
//    var logData: [Int: LogGameModel] = [:]
//    var logs: [Int] = []
//    var playerScreens: [UUID: Data] = [:]
//    var attachments: [NetworkModules: GroupSessionJournal.Attachment] = [:]
//    var metaDataAttachments: [NetworkModules: UUID] = [:]
//    
//    var masterController: MasterController?
//    var playerController: PlayerController?
//    
//    func add(playerId: UUID, playerModel: PlayerGameModel, sharingModel: SharingControlModel) -> Bool {
//        if let index = gameConfig.players.firstIndex(where: { $0.id == playerId }) {
//            gameConfig.players[index] = playerModel
//            var model = sharingModel
//            model.show = gameConfig.controls[index].show
//            gameConfig.controls[index] = model
//            return false
//        } else {
//            gameConfig.players.append(playerModel)
//            gameConfig.controls.append(sharingModel)
//            return true
//        }
//    }
//    
//    func add(playerId: UUID, sharingModel: SharingControlModel) {
//        if let index = gameConfig.players.firstIndex(where: { $0.id == playerId }) {
//            gameConfig.controls[index] = sharingModel
//        } else {
//            gameConfig.controls.append(sharingModel)
//        }
//    }
//    
//    func remove(playerId: UUID) -> Bool {
//        guard let index = gameConfig.players.firstIndex(where: { $0.id == playerId }) else { return false }
//        gameConfig.players.remove(at: index)
//        gameConfig.controls.remove(at: index)
//        return true
//    }
//    
//    func reset(gameConfig: GameConfigModel) {
//        self.gameConfig = gameConfig
//    }
//    
//    func reset(controls: [SharingControlModel]) {
//        gameConfig.controls = controls
//    }
//    
//    func reset(master: MasterGameModel) {
//        gameConfig.master = master
//    }
//
//    func reset(playerId: UUID, player: PlayerGameModel, players: [PlayerGameModel]) {
//        var updatedPlayers = players
//        if !updatedPlayers.contains(where: { $0.id == playerId }) {
//            updatedPlayers.append(player)
//        }
//        gameConfig.players = updatedPlayers
//    }
//
//    func reset(features: GameFeatureModel) {
//        gameConfig.features = features
//    }
//}
//
//public final class GameRoot: @unchecked Sendable {
//    let adventureRoot: AdventureRoot
//    let audioRoot: AudioRoot
//    let diceRoot: DiceRoot
//    let mapRoot: MapRoot
//    var networkStore: NetworkController
//    var networkProxyStore: NetworkProxyController
//    let pdfRoot: PdfRoot
//    let photoRoot: PhotoRoot
//    let spaceRoot: SpaceRoot
//    let tableRoot: TableRoot
//    let valueRoot: ValueRoot
//    let weatherRoot: WeatherRoot
//
//    let gameModel: GameModel
//
//    @MainActor
//    public init(adventureRoot: AdventureRoot, audioRoot: AudioRoot, diceRoot: DiceRoot, mapRoot: MapRoot, pdfRoot: PdfRoot, photoRoot: PhotoRoot, spaceRoot: SpaceRoot, tableRoot: TableRoot, valueRoot: ValueRoot, weatherRoot: WeatherRoot) {
//        self.adventureRoot = adventureRoot
//        self.audioRoot = audioRoot
//        self.diceRoot = diceRoot
//        self.mapRoot = mapRoot
//        self.pdfRoot = pdfRoot
//        self.photoRoot = photoRoot
//        self.spaceRoot = spaceRoot
//        self.tableRoot = tableRoot
//        self.valueRoot = valueRoot
//        self.weatherRoot = weatherRoot
//        
//        self.networkStore = NetworkController(name: "Init")
//        self.networkProxyStore = NetworkProxyController(name: "Proxy")
//        
//        self.gameModel = GameModel()
//        
//        _viewController = ViewController(root: self)
//        _logGameController = LogGameController(root: self, gameModel: gameModel)
//    }
//
//    private(set) var _viewController: ViewController?
//    public var viewController: ViewController {
//        _viewController.unsafelyUnwrapped
//    }
//    
//    private(set) var _logGameController: LogGameController?
//    var logGameController: LogGameController {
//        _logGameController.unsafelyUnwrapped
//    }
//
//    @MainActor
//    var characterName: String {
//        if let selectedCharacter = gameModel.selectedCharacter {
//            return valueRoot.linkController.name(for: selectedCharacter)
//        } else {
//            return "Unknown"
//        }
//    }
//
//    @MainActor
//    var gameMasterName: String {
//        if let selectedGameMaster = gameModel.selectedGameMaster {
//            return valueRoot.linkController.name(for: selectedGameMaster)
//        } else {
//            return "Unknown"
//        }
//    }
//}
//
//// MARK: - Master / Player selection views and handling
//
//extension GameRoot {
//    @MainActor
//    func resetSelectedAdventure(uuidString: String) {
//        guard let uuid = UUID(uuidString: uuidString) else {
//            if gameModel.selectedAdventure != nil {
//                gameModel.selectedAdventure = nil
//            }
//            return
//        }
//        gameModel.selectedAdventure <=> uuid
//    }
//
//    @MainActor
//    func resetSelectedCharacter(uuidString: String) {
//        guard let uuid = UUID(uuidString: uuidString) else {
//            if gameModel.selectedCharacter != nil {
//                gameModel.selectedCharacter = nil
//            }
//            return
//        }
//        gameModel.selectedCharacter <=> uuid
//    }
//
//    @MainActor
//    func resetSelectedGameMaster(uuidString: String) {
//        guard let uuid = UUID(uuidString: uuidString) else {
//            if gameModel.selectedGameMaster != nil {
//                gameModel.selectedGameMaster = nil
//            }
//            return
//        }
//        gameModel.selectedGameMaster <=> uuid
//    }
//}
//
//// MARK: - Master Control Game
//
//extension GameRoot {
//    @MainActor
//    func startMaster() async {
//        guard gameModel.gameConfig.state == .stopped else {
//            await stopGame()
//            return
//        }
//        guard let id = gameModel.selectedAdventure else {
//            return
//        }
//        
//        let masterGameModel = MasterGameModel(id: UUID(), type: .master, name: gameMasterName, adventureId: id, adventureTitle: adventureRoot.networkTitle(for: id))
//        gameModel.gameConfig.id = masterGameModel.id
//        gameModel.gameConfig.master = masterGameModel
//        gameModel.startGameTime = Date.now
//        
//        networkStore.resetName(name: gameMasterName)
//        networkProxyStore.resetName(name: gameMasterName)
//        networkStore.sharePlayStore.setup(audioCoordinator: audioRoot.audioCoordinatorPlayback)
//
//        adventureRoot.gameControllable.startGame(with: id)
//        gameModel.playerController = PlayerController(root: self, asGameMaster: true)
//        gameModel.masterController = MasterController(root: self, asProxy: false)
//
//        gameModel.gameConfig.state = .started
//
//        await gameModel.masterController?.start()
//        valueRoot.gameControllable.startGame(for: gameModel.selectedGameMaster!)
//        diceRoot.gameControllable.setFocusDice(on: valueRoot.gameControllable.focusDice(for: gameModel.selectedGameMaster!))
//        
//#if !os(macOS)
//        UIApplication.shared.isIdleTimerDisabled = true
//#endif
//    }
//}
//
//// MARK: - Player Control Game
//
//extension GameRoot {
//    @MainActor
//    private func name(for type: GameType) -> String {
//        switch type {
//        case .observer:
//            return "Observer"
//        case .proxy:
//            return "Proxy"
//        default:
//            return characterName
//        }
//    }
//
//    @MainActor
//    func startGame(to model: BrowserDeviceModel?, mode: GameType) async {
//        if (mode == .proxy || mode == .observer || mode == .demo) {
//            gameModel.selectedCharacter = nil
//        }
//        let playerGameModel = PlayerGameModel(id: UUID(), type: mode, name: name(for: mode), characterId: gameModel.selectedCharacter)
//        gameModel.gameConfig.players = [playerGameModel]
//        gameModel.gameConfig.id = playerGameModel.id
//        gameModel.gameConfig.state = .prepare
//        networkStore.resetName(name: name(for: mode))
//        if mode == .player {
//            networkProxyStore.resetName(name: characterName)
//            networkStore.sharePlayStore.setup(audioCoordinator: audioRoot.audioCoordinatorPlayback)
//        }
//
//        adventureRoot.gameControllable.resetGame()
//        let player = PlayerController(root: self, asGameMaster: mode == .demo)
//        gameModel.playerController = player
//
//        if mode == .demo {
//            joinGame(for: mode)
//
//#if !os(macOS)
//            UIApplication.shared.isIdleTimerDisabled = true
//#endif
//        } else if await player.start(to: model) {
//            joinGame(for: mode)
//
//#if !os(macOS)
//            UIApplication.shared.isIdleTimerDisabled = true
//#endif
//        } else {
//            await stopGame()
//        }
//    }
//
//    @MainActor
//    func joinGame(for type: GameType) {
//        gameModel.startGameTime = Date.now
//        gameModel.playerGameStarted = true
//        gameModel.gameConfig.players[0].type = type
//        gameModel.gameConfig.players[0].name = name(for: type)
//        gameModel.gameConfig.state = .started
//        if type != .observer {
//            valueRoot.gameControllable.startGame(for: gameModel.selectedCharacter)
//            diceRoot.gameControllable.setFocusDice(on: valueRoot.gameControllable.focusDice(for: gameModel.selectedCharacter ?? UUID()))
//        }
//    }
//
//    // both
//    @MainActor
//    func stopGame() async {
//        gameModel.playerGameStarted = false
//        gameModel.gameConfig.state = .stopped
//        gameModel.gameConfig = .empty
//        await gameModel.masterController?.stop()
//        gameModel.masterController = nil
//        await gameModel.playerController?.stop()
//        gameModel.playerController = nil
//        adventureRoot.gameControllable.resetGame()
//
//#if !os(macOS)
//        UIApplication.shared.isIdleTimerDisabled = false
//#endif
//    }
//
//    @MainActor
//    func saveGame() -> (Task<Void, any Error>, URL) {
//        adventureRoot.gameControllable.saveGame()
//    }
//}
//
//// MARK: - Demo
//
//extension GameRoot {
//    @MainActor
//    func startDemo() async {
//        await startGame(to: nil, mode: .demo)
//
//        if let playerController = gameModel.playerController {
//            Task {
//                while gameModel.gameConfig.state != .stopped {
//                    let photos = photoRoot.itemControllable.itemDataModel.items
//                    for photo in photos {
//                        try await Task.sleep(for: .seconds(3))
//                        let data = await photoRoot.gameControllable.share(id: photo)
//                        let gameNetworkModel = GameNetworkModel(counter: 1, proxyCounter: 0, type: .reveal, subType: .show, gameConfig: gameModel.gameConfig, data: data)
//                        await playerController.receivedProcess(gameNetworkModel)
//                    }
//                    
//                    let weathers = weatherRoot.itemControllable.itemDataModel.items
//                    for weather in weathers {
//                        try await Task.sleep(for: .seconds(5))
//                        let data = await weatherRoot.gameControllable.share(id: weather)
//                        let gameNetworkModel = GameNetworkModel(counter: 2, proxyCounter: 0, type: .reveal, subType: .show, gameConfig: gameModel.gameConfig, data: data)
//                        await playerController.receivedProcess(gameNetworkModel)
//                    }
//                    
//                    let maps = mapRoot.itemControllable.itemDataModel.items
//                    for map in maps {
//                        try await Task.sleep(for: .seconds(5))
//                        let data = await mapRoot.gameControllable.share(id: map)
//                        let gameNetworkModel = GameNetworkModel(counter: 2, proxyCounter: 0, type: .reveal, subType: .show, gameConfig: gameModel.gameConfig, data: data)
//                        await playerController.receivedProcess(gameNetworkModel)
//                        
//                        var showMap = true
//                        
//                        while showMap {
//                            var data = mapRoot.gameControllable.demoNextMap(itemId: map, restart: false)
//                            if data == nil {
//                                data = mapRoot.gameControllable.demoNextMap(itemId: map, restart: true)
//                                showMap = false
//                            }
//                            guard let data else { break }
//                            try await Task.sleep(for: .seconds(3))
//                            
//                            let gameNetworkModel = GameNetworkModel(counter: 2, proxyCounter: 0, type: .update, subType: .mapState, gameConfig: gameModel.gameConfig, data: data)
//                            await playerController.receivedProcess(gameNetworkModel)
//                        }
//                    }
//                }
//            }
//        }
//    }
//}
//
//public extension GameRoot {
//    func networkActions() -> NetworkActions {
//        NetworkActions { @MainActor [weak self] idType in
//            guard let store = self?.gameModel.masterController else { return }
//            Task {
//                await store.show(for: idType)
//            }
//        } send: { @MainActor [weak self] update in
//            let masterStore = self?.gameModel.masterController
//            let playerStore = self?.gameModel.playerController
//            
//            Task {
//                if let masterStore {
//                    await masterStore.send(updated: update)
//                } else {
//                    await playerStore?.send(updated: update)
//                }
//            }
//        } game: { @MainActor [weak self] message, actionType in
//            let masterStore = self?.gameModel.masterController
//            let playerStore = self?.gameModel.playerController
//            
//            Task {
//                if let masterStore {
//                    await masterStore.game(message: message, actionType: actionType)
//                } else {
//                    await playerStore?.game(message: message, actionType: actionType)
//                }
//            }
//        }
//    }
//    
//    @MainActor
//    var sharingControlActions: SharingControlActions {
//        SharingControlActions { [weak self] in
//            self?.gameModel.gameConfig.controls ?? []
//        } update: { [weak self] newControls in
//            if self?.gameModel.gameConfig.controls != newControls {
//                self?.gameModel.gameConfig.controls = newControls
//            }
//            Task {
//                await self?.gameModel.masterController?.resetPlayers()
//            }
//        }
//    }
//    
//    @MainActor
//    var sharingFeatureActions: SharingFeatureActions {
//        SharingFeatureActions { [weak self] in
//            self?.gameModel.gameConfig.features ?? GameFeatureModel()
//        }
//    }
//}
