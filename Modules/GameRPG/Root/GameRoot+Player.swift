// @copyright André Trettin

import AdventureRPG
import CoreRPG
import DiceRPG
import Foundation
import GroupActivities
import os.log
import AudioRPG
import MapRPG
import PdfRPG
import PhotoRPG
import RuleRPG
import SpaceRPG
import TableRPG
import CharacterRPG
import SwiftUI
import WeatherRPG

// MARK: - Player Control Game

extension GameRoot {
    private func name(for type: GameType) -> String {
        switch type {
        case .observer:
            return String(localized: "Observer", bundle: .module)
        case .proxy:
            return String(localized: "Proxy", bundle: .module)
        default:
            return characterName
        }
    }

    func startGame(
        to model: BrowserGameModel?,
        mode: GameType,
        supporterTier: SupporterTier = .none,
        joinCode: String = ""
    ) async {
        await awaitInFlightStop()
        guard !isStartingGame, !isStartingMaster else {
            Logger.networking.info("GameRoot: startGame ignored, another start is still running")
            return
        }
        isStartingGame = true
        defer { isStartingGame = false }
        let generation = stopGeneration
        // Observer is intentionally Bonjour/LAN-only. Enforce this at the domain
        // boundary as well as in the setup UI so programmatic callers cannot join
        // SharePlay by passing a nil target.
        guard mode != .observer || model != nil else { return }
        if (mode == .proxy || mode == .observer || mode == .demo) {
            gameModel.selectedCharacter = nil
        }
        let playerGameModel = PlayerGameModel(
            id: UUID(),
            type: mode,
            name: name(for: mode),
            characterId: gameModel.selectedCharacter,
            supporterTier: supporterTier,
            companions: mode == .player ? Self.storedCompanions(for: gameModel.selectedCharacter) : []
        )
        gameModel.gameRoster = GameRosterModel(players: [playerGameModel])
        gameModel.gameControl = .empty
        var newConfig = gameModel.gameConfig
        newConfig.id = playerGameModel.id
        newConfig.state = .prepare
        gameModel.gameConfig = newConfig
        networkStore.resetName(name: name(for: mode), supporterTier: supporterTier)
        if mode == .player {
            networkProxyStore.resetName(name: characterName, supporterTier: supporterTier)
            networkStore.sharePlayStore.setup(audioCoordinator: audioRoot.audioCoordinatorPlayback)
            installAudioCoordinatorChangeHandler()
        }

        await adventureRoot.adventureGameControllable.resetGame()
        guard generation == stopGeneration else { return }
        #if os(visionOS)
        gameModel.shareState.isMaster = false
        #endif
        // Game mode before the player controller can process anything: a package the master
        // sends while connecting was written to the permanent library otherwise. A failed start
        // resets it again in `stopGame()`. See CODE_AUDIT_Folder §5.25.
        adventureRoot.startGame()
        let player = PlayerController(root: self, asGameMaster: mode == .demo)
        gameModel.playerController = player

        if mode == .demo {
            await joinGame(for: mode, supporterTier: supporterTier)

            KeepAwakeModel.shared.acquire(.game)
        } else if await player.start(to: model, joinCode: joinCode) {
            // A stop during the connect already tore the game down.
            guard generation == stopGeneration else { return }
            await joinGame(for: mode, supporterTier: supporterTier)

            KeepAwakeModel.shared.acquire(.game)
        } else {
            await stopGame()
        }
    }

    func joinGame(
        for type: GameType,
        supporterTier: SupporterTier = .none
    ) async {
        gameModel.startGameTime = Date.now
        gameModel.playerGameStarted = true
        var newConfig = gameModel.gameConfig
        newConfig.state = .started
        gameModel.gameConfig = newConfig
        let companions = type == .player ? Self.storedCompanions(for: gameModel.selectedCharacter) : []
        // Update the local player by id, not by index: a master broadcast
        // processed during connect can already have replaced the roster, and
        // index 0 may then be another player's entry.
        if let index = gameModel.gameRoster.players.firstIndex(where: { $0.id == gameModel.gameConfig.id }) {
            gameModel.gameRoster.players[index].type = type
            gameModel.gameRoster.players[index].name = name(for: type)
            gameModel.gameRoster.players[index].characterId = gameModel.selectedCharacter
            gameModel.gameRoster.players[index].supporterTier = supporterTier
            gameModel.gameRoster.players[index].companions = companions
        } else {
            gameModel.gameRoster.players.append(
                PlayerGameModel(
                    id: gameModel.gameConfig.id,
                    type: type,
                    name: name(for: type),
                    characterId: gameModel.selectedCharacter,
                    supporterTier: supporterTier,
                    companions: companions
                )
            )
        }
        adventureRoot.startGame()
        if type != .observer {
            await characterRoot.valueGameControllable.startGame(for: gameModel.selectedCharacter)
            await diceRoot.diceGameControllable.setFocusDice(on: characterRoot.valueGameControllable.focusDice(for: gameModel.selectedCharacter ?? UUID()))
        }
        await beginStatisticsSession(for: type, at: gameModel.startGameTime)
    }

    // both

    func saveGame() -> ItemModuleIds {
        adventureRoot.adventureGameControllable.saveGame()
    }
}
