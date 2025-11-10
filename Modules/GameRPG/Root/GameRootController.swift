// @copyright André Trettin

import AdventureRPG
import AudioRPG
import CharacterRPG
import DiceRPG
import MapRPG
import PdfRPG
import PhotoRPG
import SpaceRPG
import TableRPG
import WeatherRPG

import CoreRPG
import Foundation
import SwiftData
#if !os(macOS)
import UIKit
#endif

@Observable
public final class GameRootController: Sendable {
    @MainActor init(root: RootManager, adventureRoot: AdventureRootModel, audioRoot: AudioRootModel, characterRoot: CharacterRootModel, diceRoot: DiceRootModel, mapRoot: MapRootModel, pdfRoot: PdfRootModel, photoRoot: PhotoRootModel, spaceRoot: SpaceRootModel, tableRoot: TableRootModel, weatherRoot: WeatherRootModel) {
        self.gameModel = GameRootModel()
        self.root = root
        self.adventureRoot = adventureRoot
        self.audioRoot = audioRoot
        self.characterRoot = characterRoot
        self.diceRoot = diceRoot
        self.mapRoot = mapRoot
        self.pdfRoot = pdfRoot
        self.photoRoot = photoRoot
        self.spaceRoot = spaceRoot
        self.tableRoot = tableRoot
        self.weatherRoot = weatherRoot
        self.networkStore = NetworkController(name: "Init")
        self.networkProxyStore = NetworkProxyController(name: "Proxy")
        
        self.logGameController = LogGameController(root: root, gameModel: gameModel)
    }
    let root: RootManager
    let adventureRoot: AdventureRootModel
    let audioRoot: AudioRootModel
    let characterRoot: CharacterRootModel
    let diceRoot: DiceRootModel
    let mapRoot: MapRootModel
    let pdfRoot: PdfRootModel
    let photoRoot: PhotoRootModel
    let spaceRoot: SpaceRootModel
    let tableRoot: TableRootModel
    let weatherRoot: WeatherRootModel
    
    let logGameController: LogGameController
    let networkStore: NetworkController
    let networkProxyStore: NetworkProxyController

    let gameModel: GameRootModel
    
    public let viewController: ViewController = ViewController()
}


// MARK: - Master / Player selection views and handling

extension GameRootController {
    @MainActor func resetSelectedAdventure(uuidString: String) {
        guard let uuid = UUID(uuidString: uuidString) else {
            if gameModel.selectedAdventure != nil {
                gameModel.selectedAdventure = nil
            }
            return
        }
        gameModel.selectedAdventure <=> uuid
    }

    @MainActor func resetSelectedCharacter(uuidString: String) {
        guard let uuid = UUID(uuidString: uuidString) else {
            if gameModel.selectedCharacter != nil {
                gameModel.selectedCharacter = nil
            }
            return
        }
        gameModel.selectedCharacter <=> uuid
    }

    @MainActor func resetSelectedGameMaster(uuidString: String) {
        guard let uuid = UUID(uuidString: uuidString) else {
            if gameModel.selectedGameMaster != nil {
                gameModel.selectedGameMaster = nil
            }
            return
        }
        gameModel.selectedGameMaster <=> uuid
    }
    
    @MainActor
    var characterName: String {
        if let selectedCharacter = gameModel.selectedCharacter {
            return root[.value]!.linkControllable.name(for: selectedCharacter)
        } else {
            return "Unknown"
        }
    }

    @MainActor
    var gameMasterName: String {
        if let selectedGameMaster = gameModel.selectedGameMaster {
            return root[.value]!.linkControllable.name(for: selectedGameMaster)
        } else {
            return "Unknown"
        }
    }
}

// MARK: - Master Control Game

extension GameRootController {
    @MainActor
    func startMaster() async {
        guard gameModel.gameConfig.state == .stopped else {
            await stopGame()
            return
        }
        guard let id = gameModel.selectedAdventure else {
            return
        }
        
        let masterGameModel = MasterGameModel(id: UUID(), type: .master, name: gameMasterName, adventureId: id, adventureTitle: adventureRoot.itemControllable.item(for: id)?.name)
        gameModel.gameConfig.id = masterGameModel.id
        gameModel.gameConfig.master = masterGameModel
        gameModel.startGameTime = Date.now
        
        networkStore.resetName(name: gameMasterName)
        networkProxyStore.resetName(name: gameMasterName)
        networkStore.sharePlayStore.setup(audioCoordinator: audioRoot.gameController.audioCoordinatorPlayback)

        adventureRoot.gameControllable.startGame(with: id)
        gameModel.playerController = PlayerController(root: self, asGameMaster: true)
        gameModel.masterController = MasterController(root: self, asProxy: false)

        gameModel.gameConfig.state = .started

        await gameModel.masterController?.start()
        characterRoot.gameController.startGame(for: gameModel.selectedGameMaster!)
        diceRoot.gameController.setFocusDice(on: characterRoot.gameController.focusDice(for: gameModel.selectedGameMaster!))
        
#if !os(macOS)
        UIApplication.shared.isIdleTimerDisabled = true
#endif
    }
}

// MARK: - Player Control Game

extension GameRootController {
    @MainActor
    func startGame(to model: BrowserDeviceModel?, mode: GameType) async {
        if (mode == .proxy || mode == .observer || mode == .demo) {
            gameModel.selectedCharacter = nil
        }
        let playerGameModel = PlayerGameModel(id: UUID(), type: mode, name: name(for: mode), characterId: gameModel.selectedCharacter)
        gameModel.gameConfig.players = [playerGameModel]
        gameModel.gameConfig.id = playerGameModel.id
        gameModel.gameConfig.state = .prepare
        networkStore.resetName(name: name(for: mode))
        if mode == .player {
            networkProxyStore.resetName(name: characterName)
            networkStore.sharePlayStore.setup(audioCoordinator: audioRoot.gameController.audioCoordinatorPlayback)
        }

        adventureRoot.gameController.resetGame()
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
        gameModel.gameConfig.players[0].type = type
        gameModel.gameConfig.players[0].name = name(for: type)
        gameModel.gameConfig.state = .started
        if type != .observer {
            characterRoot.gameController.startGame(for: gameModel.selectedCharacter)
            diceRoot.gameController.setFocusDice(on: characterRoot.gameController.focusDice(for: gameModel.selectedCharacter ?? UUID()))
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
        adventureRoot.gameController.resetGame()

#if !os(macOS)
        UIApplication.shared.isIdleTimerDisabled = false
#endif
    }

    @MainActor
    func saveGame() -> (Task<Void, any Error>, URL) {
        adventureRoot.gameController.saveGame()
    }

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
}

// MARK: - Demo

extension GameRootController {
    @MainActor
    func startDemo() async {
        await startGame(to: nil, mode: .demo)

        if let playerController = gameModel.playerController {
            Task {
                while gameModel.gameConfig.state != .stopped {
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
                }
            }
        }
    }
}

public extension GameRootController {
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
}
