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

// MARK: - Master Control Game

extension GameRoot {
    func startMaster(supporterTier: SupporterTier = .none) async {
        // Checked and set before the first suspension: a call that arrives while a start is
        // running is ignored, it neither starts a second game nor stops the one being started.
        // A start of either kind blocks the other: a Siri join racing a master start used to
        // tear the other down.
        guard !isStartingMaster, !isStartingGame else { return }
        isStartingMaster = true
        defer { isStartingMaster = false }
        await awaitInFlightStop()
        let generation = stopGeneration
        guard gameModel.gameConfig.state == .stopped else {
            await stopGame()
            return
        }
        guard let id = gameModel.selectedAdventure else {
            return
        }

        let adventureTitle = adventureRoot.networkTitle(for: id)
        let masterGameModel = MasterGameModel(
            id: UUID(),
            type: .master,
            name: gameMasterName,
            adventureId: id,
            adventureTitle: adventureTitle,
            supporterTier: supporterTier
        )
        var newConfig = gameModel.gameConfig
        newConfig.id = masterGameModel.id
        newConfig.master = masterGameModel
        gameModel.gameConfig = newConfig
        gameModel.startGameTime = Date.now
        #if os(visionOS)
        gameModel.shareState.isMaster = true
        #endif

        // Bonjour advertises the adventure title (falling back to "GameMaster"
        // when it's empty) plus the supporter tier, so browsing players see
        // what adventure they're joining rather than a generic device label.
        let advertisedName = adventureTitle.isEmpty ? gameMasterName : adventureTitle
        networkStore.resetName(name: advertisedName, supporterTier: supporterTier)
        networkProxyStore.resetName(name: advertisedName, supporterTier: supporterTier)
        networkStore.sharePlayStore.setup(audioCoordinator: audioRoot.audioCoordinatorPlayback)
        installAudioCoordinatorChangeHandler()

        await adventureRoot.adventureGameControllable.startGame(with: id)
        guard generation == stopGeneration else { return }
        gameModel.playerController = PlayerController(root: self, asGameMaster: true)
        gameModel.masterController = MasterController(root: self, asProxy: false)
        gameModel.tablePlayers = adventureRoot.adventureGameControllable.tablePlayers(for: id)

        gameModel.gameConfig.state = .started
        adventureRoot.startGame()

        await beginStatisticsSession(for: .master, at: gameModel.startGameTime)

        await gameModel.masterController?.start()
        if !gameModel.tablePlayers.isEmpty {
            // The table players' pins wait for the first shown map like a joined player's.
            await gameModel.masterController?.resetPlayers()
        }
        await diceRoot.diceGameControllable.setFocusDice(on: adventureRoot.adventureGameControllable.focusDice(for: id))
        guard generation == stopGeneration else { return }
#if !os(tvOS)
        adventureRoot.donateStartGame(of: id)
#endif

        KeepAwakeModel.shared.acquire(.game)
    }
}
