// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftUI
import os.log

import AdventureRPG
import CharacterRPG
import GameRPG

#if !os(tvOS)
extension AppModel {
    /// Connects the content widgets and the game intents to the models they read, once at launch.
    /// See CODE_AUDIT_Since_3.0.1 §9.12.
    func connectIntentsAndWidgets() {
        let characterDataModel = characterRoot.itemControllable.itemDataModel
        characterDataModel.contentWidgetPublisher = { [weak characterDataModel] in
            guard let characterDataModel else { return }
            ContentWidgetSnapshot.publish(module: .value, from: characterDataModel)
        }

        let adventureDataModel = adventureRoot.itemControllable.itemDataModel
        adventureDataModel.contentWidgetPublisher = { [weak adventureDataModel] in
            guard let adventureDataModel else { return }
            ContentWidgetSnapshot.publish(module: .adventure, from: adventureDataModel)
        }

        // What the game screens get from the environment, for intents that act like them.
        // See CODE_AUDIT_AppIntents3 §5.3.
        let gameStateModel = appGameStateModel
        let gameRoot = gameRoot
        IntentGameContext.networkActions = { [weak gameStateModel, weak gameRoot] in
            guard let gameStateModel, gameStateModel.isGameRunning, let gameRoot else { return nil }
            return gameRoot.networkActions
        }
        IntentGameContext.gameModus = { [weak gameStateModel] in
            guard let gameStateModel, gameStateModel.isGameRunning else { return nil }
            return gameStateModel.gameModus
        }
        IntentGameContext.canControlGameAudio = { [weak gameStateModel, weak gameRoot] in
            guard let gameStateModel, let gameRoot else { return true }
            return gameStateModel.gameModus == .master || gameRoot.isAudioSharingEnabled
        }
        IntentGameContext.supporterTier = { [weak self] in self?.supporterTier ?? .none }
        IntentGameContext.nextTurn = { [weak gameRoot] in gameRoot?.nextTurn() }
        IntentGameContext.setGameState = { [weak gameStateModel] isRunning, modus in
            guard let gameStateModel else { return }
            if gameStateModel.isGameRunning != isRunning { gameStateModel.isGameRunning = isRunning }
            if gameStateModel.gameModus != modus { gameStateModel.gameModus = modus }
        }
    }
}
#endif
