// @copyright André Trettin


import CoreRPG
import CoreData
import Observation
import SwiftUI
import os.log

import AdventureRPG
import DiceRPG
import AudioRPG
import GameRPG
import MapRPG
import PdfRPG
import PhotoRPG
import RPGResources
import RuleRPG
import SpaceRPG
import TableRPG
import CharacterRPG
import WeatherRPG

#if !os(tvOS)
import GeneratorRPG
#endif

// The window placement around the game window, split out of AppModel.swift. See CODE_AUDIT_29 §9.9.

extension AppModel {
    /// The window the game shows its content in: the adventure viewer for the master, the
    /// character viewer for the player. The table, audio and photo windows are placed around it.
    private var gameViewWindowId: String {
        appGameStateModel.gameModus == .player
            ? NetworkModules.value.viewerWindowId
            : NetworkModules.adventure.viewerWindowId
    }

    public func windowPlacement(for module: NetworkModules, isViewer: Bool = false) -> WindowPlacementPosition {
        switch module {
        case .none, .setting, .editor, .game, .generator, .search:
            return .leading(SceneId.game.rawValue)
        case .photo:
            return .below(gameViewWindowId, fallback: SceneId.game.rawValue)
        case .map:
            return .trailing(NetworkModules.adventure.linkWindowId, fallback: SceneId.game.rawValue)
        case .table:
            return .leading(gameViewWindowId, fallback: SceneId.game.rawValue)
        case .adventure:
            return .leading(SceneId.game.rawValue)
        case .dice:
            return .above(SceneId.game.rawValue)
        case .weather:
            return .above(NetworkModules.map.linkWindowId, fallback: SceneId.game.rawValue)
        case .value:
            // The player's character viewer is the game view itself; only the link window
            // goes above the Game window.
            if isViewer, appGameStateModel.gameModus == .player {
                return .leading(SceneId.game.rawValue, fallback: nil)
            }
            return .above(SceneId.game.rawValue)

        case .audio:
            return .above(gameViewWindowId, fallback: SceneId.game.rawValue)
        case .pdf:
            return .below(SceneId.game.rawValue)
        case .rule:
            return .trailing(NetworkModules.pdf.linkWindowId, fallback: SceneId.game.rawValue)
        case .space:
            return .below(SceneId.game.rawValue)
        @unknown default:
            return .leading(SceneId.game.rawValue)
        }
    }
}
