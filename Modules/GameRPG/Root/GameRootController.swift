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
internal import UIKit
#endif

public struct GameRootController {
    @MainActor init(adventureRoot: AdventureRootModel, audioRoot: AudioRootModel, characterRoot: CharacterRootModel, diceRoot: DiceRootModel, mapRoot: MapRootModel, pdfRoot: PdfRootModel, photoRoot: PhotoRootModel, spaceRoot: SpaceRootModel, tableRoot: TableRootModel, weatherRoot: WeatherRootModel) {
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
        
        self.gameModel = GameRootModel()
        
        self.networkStore = NetworkController(name: "Init")
        self.networkProxyStore = NetworkProxyController(name: "Proxy")
    }
    
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
    
    let gameModel: GameRootModel
    
    let networkStore: NetworkController
    let networkProxyStore: NetworkProxyController

    //static let preview = GameRootController(adventureRoot: AdventureRootModel(, gameModel: <#T##GameRootModel#>)
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
            return characterRoot.linkControllable.name(for: selectedCharacter)
        } else {
            return "Unknown"
        }
    }

    @MainActor
    var gameMasterName: String {
        if let selectedGameMaster = gameModel.selectedGameMaster {
            return characterRoot.linkControllable.name(for: selectedGameMaster)
        } else {
            return "Unknown"
        }
    }
}


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
//            networkStore.sharePlayStore.setup(audioCoordinator: audioRoot.audioCoordinatorPlayback)
        }

//        adventureRoot.gameControllable.resetGame()
//        let player = PlayerController(root: self, asGameMaster: mode == .demo)
//        gameModel.playerController = player

        if mode == .demo {
            joinGame(for: mode)

#if !os(macOS)
            UIApplication.shared.isIdleTimerDisabled = true
#endif
//        } else if await player.start(to: model) {
//            joinGame(for: mode)
//
//#if !os(macOS)
//            UIApplication.shared.isIdleTimerDisabled = true
//#endif
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
//            characterRoot.gameControllable.startGame(for: gameModel.selectedCharacter)
//            diceRoot.gameControllable.setFocusDice(on: characterRoot.gameControllable.focusDice(for: gameModel.selectedCharacter ?? UUID()))
        }
    }

    // both
    @MainActor
    func stopGame() async {
        gameModel.playerGameStarted = false
        gameModel.gameConfig.state = .stopped
        gameModel.gameConfig = .empty
//        await gameModel.masterController?.stop()
//        gameModel.masterController = nil
//        await gameModel.playerController?.stop()
//        gameModel.playerController = nil
//        adventureRoot.gameControllable.resetGame()

#if !os(macOS)
        UIApplication.shared.isIdleTimerDisabled = false
#endif
    }

//    @MainActor
//    func saveGame() -> (Task<Void, any Error>, URL) {
//        adventureRoot.gameControllable.saveGame()
//    }

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
