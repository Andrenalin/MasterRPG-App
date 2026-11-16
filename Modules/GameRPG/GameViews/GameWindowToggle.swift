// @copyright André Trettin

import CoreRPG
import SwiftUI

/// Opens or closes the floating "game window" — the master's adventure
/// content, or a player's active character sheet — the same window
/// `GameWindowMenuButtonView` toggles (extracted from its `isMaster`-merged
/// `toggleGameWindow` so `GameTableWindowButton` can drive the same window
/// from the 3D table side, keeping the table and this window mutually
/// exclusive on visionOS).
@MainActor
enum GameWindowToggle {
    /// Fixed delay `MasterGameScreen`/`PlayerGameScreen` wait out before opening their
    /// adventure/character viewer window during game-screen entry — a timing heuristic,
    /// not a true readiness signal: `ScenesManager` has no completion callback for "the
    /// game screen itself has finished settling" to await instead. Named and shared here
    /// so both screens' `prepareWindows()` don't hand-duplicate the literal. See CODE_AUDIT §5.2.
    static let windowPrepDelay: Duration = .seconds(0.6)

    static func sceneId(isMaster: Bool) -> SceneId {
        SceneId.viewerId(for: isMaster ? .adventure : .value)
    }

    /// `itemId` is the adventure id for the master (available once a game is
    /// running) or the selected character id for a player (`nil` when no
    /// character is selected yet, in which case this is a no-op — matches
    /// `GameWindowMenuButtonView`'s own player-side disabled guard).
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

#if os(visionOS)
    /// The secondary windows a game opens: each module's viewer and link windows (the adventure
    /// game view among them), the battle round, the 3D table and the spatial viewers.
    private static var secondaryScenes: [SceneId] {
        let moduleScenes = NetworkModules.allCases
            .filter { $0.linkWindowId != "NoWindow" }
            .flatMap { [SceneId.sceneId(for: $0), SceneId.viewerId(for: $0)] }
        return moduleScenes + [.battleRound, .gameTable, .gameRecover, .imageSpaceViewer, .weatherSpaceViewer]
    }

    /// Closes every secondary window and the immersive space when the game quits, so none stays
    /// behind with nothing to show. The game screen itself is left to the navigation.
    static func closeSecondaryWindows(scenesManager: ScenesManager) async {
        for scene in secondaryScenes where scenesManager.getSceneState(for: scene) != .closed {
            scenesManager.dismissWindow(scene)
        }
        if scenesManager.immersiveSpaceState == .open {
            await scenesManager.toggleSpaceViewer(selection: nil)
        }
    }
#endif
}
