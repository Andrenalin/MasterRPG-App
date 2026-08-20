// @copyright André Trettin

import CoreRPG
import SwiftUI

/// Opens or closes the floating "game window" — the master's adventure
/// content, or a player's active character sheet — the same window
/// `MasterGameWindowButtonView`/`PlayerGameWindowButtonView` toggle
/// (extracted from their near-identical `toggleGameWindow` implementations
/// so `GameTableWindowButton` can drive the same window from the 3D table
/// side, keeping the table and this window mutually exclusive on visionOS).
@MainActor
enum GameWindowToggle {
    static func sceneId(isMaster: Bool) -> SceneId {
        SceneId.viewerId(for: isMaster ? .adventure : .value)
    }

    /// `itemId` is the adventure id for the master (available once a game is
    /// running) or the selected character id for a player (`nil` when no
    /// character is selected yet, in which case this is a no-op — matches
    /// `PlayerGameWindowButtonView`'s own original guard).
    static func open(
        isMaster: Bool,
        itemId: UUID?,
        scenesManager: ScenesManager,
        gameScreenModel: GameScreenModel,
        appSettingsModel: AppSettingsModel,
        animated: Bool
    ) {
        guard let itemId else { return }
        withAnimation(animated ? .default : nil) {
            gameScreenModel.showMainTab = .none
            gameScreenModel.gameMainTabDisplayMode = .window
        }
        if isMaster {
            appSettingsModel.masterMainTabDisplayMode = GameMainTabDisplayMode.window.rawValue
        } else {
            appSettingsModel.playerMainTabDisplayMode = GameMainTabDisplayMode.window.rawValue
        }
        scenesManager.openWindow(sceneId(isMaster: isMaster), selection: WindowItemSelection(itemId: itemId))
    }

    static func close(
        isMaster: Bool,
        scenesManager: ScenesManager,
        gameScreenModel: GameScreenModel,
        appSettingsModel: AppSettingsModel
    ) {
        scenesManager.dismissWindow(sceneId(isMaster: isMaster))
        gameScreenModel.gameMainTabDisplayMode = .hidden
        if isMaster {
            appSettingsModel.masterMainTabDisplayMode = GameMainTabDisplayMode.hidden.rawValue
        } else {
            appSettingsModel.playerMainTabDisplayMode = GameMainTabDisplayMode.hidden.rawValue
        }
    }
}
