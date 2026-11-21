// @copyright André Trettin

import CoreRPG
import SwiftUI

/// Decides whether a game screen opens the 3D table by itself when its game starts (visionOS).
/// Pure, so it is unit-tested on every platform.
struct GameTableAutoOpenPolicy: Equatable {
    /// Open only while the game runs, is not being quit, the table is not already (being) shown
    /// and this game screen has not opened it before, so a table the user closed stays closed.
    static func shouldOpen(
        isGameRunning: Bool,
        isStopping: Bool,
        gameState: GameState,
        tableSceneState: ScenesManager.SceneState,
        alreadyOpened: Bool
    ) -> Bool {
        guard isGameRunning, !isStopping, gameState != .stopped, !alreadyOpened else { return false }
        switch tableSceneState {
        case .closed, .closing: return true
        case .opening, .opened: return false
        }
    }
}

#if os(visionOS)
/// Opens the 3D table window on visionOS and pushes the game window aside with the "Recover"
/// window, because the game screen itself must stay alive: it hosts the game's logic and quits the
/// game when it disappears. Shared by the table button and the automatic open at game start.
@MainActor
enum GameTableLauncher {
    /// True while a push is under way, so the button and the automatic open cannot push twice.
    private static var isOpening = false

    /// Opens the table once the recover window stands where the game window was: the system opens
    /// a new window in front of the app's existing windows, so the table lands in front of the
    /// recover window. Opens it anyway after about a second, so the table can never stay
    /// unreachable.
    static func open(
        scenesManager: ScenesManager,
        appSettingsModel: AppSettingsModel,
        pushWindow: PushWindowAction
    ) async {
        guard !isOpening else { return }
        isOpening = true
        defer { isOpening = false }
        appSettingsModel.showGameTableVolume = true
        pushWindow(id: SceneId.gameRecover.rawValue)
        for _ in 0..<20 {
            if scenesManager.getSceneState(for: SceneId.gameRecover) == .opened { break }
            guard (try? await Task.sleep(for: .milliseconds(50))) != nil else { break }
        }
        scenesManager.openWindow(SceneId.gameTable)
    }
}
#endif
