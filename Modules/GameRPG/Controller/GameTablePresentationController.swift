// @copyright André Trettin

import CoreRPG
import Foundation
import MapRPG
import SwiftUI

/// Decides whether a started game opens its 3D table by itself (visionOS). Pure, so it is
/// unit-tested on every platform.
struct GameTableAutoOpenPolicy: Equatable {
    /// Open only while the game runs, is not being quit, the table is not already (being) shown
    /// and this game has not opened it before, so a table the user closed stays closed.
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

/// Shows and hides the game's 3D table, so no view has to know how.
///
/// - iOS, macOS: the table replaces the 2D map in place within the game window
///   (`AppSettingsModel.showGameTableVolume`), switched by the table button.
/// - visionOS: the table *is* the game. The start window (`SceneId.game`) only starts it: once the
///   game runs it opens the table, then closes itself. The table window owns the game's lifetime
///   from then on, and ending the game (the seat's Quit button, the table window closed, or the
///   game stopped by the network) opens the start window again. See `openAtGameStart()` and
///   `endGame()`.
///
/// Stateless: what it remembers lives in `GameTablePresentationModel` on the game's root model.
@MainActor
struct GameTablePresentationController {
    let root: GameRoot
#if os(visionOS)
    let scenesManager: ScenesManager
    /// Mirrors the game's running state for the app's navigation; absent in a bare scene.
    let appGameStateModel: AppGameStateModel?
#else
    let appSettingsModel: AppSettingsModel
#endif

    private var model: GameTablePresentationModel { root.gameModel.tablePresentation }
}

#if !os(visionOS)
extension GameTablePresentationController {
    /// Whether the 3D table is shown in place of the map.
    var isPresented: Bool { appSettingsModel.showGameTableVolume }

    /// The table button's action.
    func toggle() {
        appSettingsModel.showGameTableVolume.toggle()
    }
}
#else
extension GameTablePresentationController {
    /// A game starts at the 3D table: opens it once per game, as soon as the game runs.
    func openAtGameStart() async {
        // The start window can show the running game a moment before the state turns to started.
        for _ in 0..<20 where root.gameModel.gameConfig.state != .started {
            guard (try? await Task.sleep(for: .milliseconds(50))) != nil else { return }
        }
        let gameId = root.gameModel.gameConfig.id
        guard GameTableAutoOpenPolicy.shouldOpen(
            isGameRunning: root.gameModel.gameConfig.state == .started,
            isStopping: root.isStopping || model.isEndingGame,
            gameState: root.gameModel.gameConfig.state,
            tableSceneState: scenesManager.getSceneState(for: SceneId.gameTable),
            alreadyOpened: model.autoOpenedGameId == gameId
        ) else { return }
        model.autoOpenedGameId = gameId
        await showTable()
    }

    /// Opens the table and the game master's adventure / the player's character window next to
    /// it, then closes the start window. The start window stays, with its button to try again,
    /// when the table does not come up, so the app never ends up without a window.
    func showTable() async {
        guard !model.isOpening else { return }
        model.isOpening = true
        defer { model.isOpening = false }
        scenesManager.openWindow(SceneId.gameTable)
        var stands = false
        for _ in 0..<40 {
            if scenesManager.getSceneState(for: SceneId.gameTable) == .opened { stands = true; break }
            guard (try? await Task.sleep(for: .milliseconds(50))) != nil else { return }
        }
        guard stands, root.gameModel.gameConfig.state == .started else { return }
        openGameWindow()
        scenesManager.dismissWindow(SceneId.game)
    }

    /// Ends the game and shows the start window again. Safe to call from every path that ends a
    /// game: the first call does the work, the others return at once.
    func endGame() async {
        guard !model.isEndingGame else { return }
        model.isEndingGame = true
        model.asksToQuit = false
        defer { model.isEndingGame = false }
        appGameStateModel?.isGameRunning = false
        root.mapRoot.rootModel.clearGameEditorSession()
        // The start window first, so the app never has no window while the table closes.
        showStartWindowIfNeeded()
        await GameWindowToggle.closeSecondaryWindows(scenesManager: scenesManager)
        await root.stopGame()
    }

    /// The table window went away while the game still runs, by the system's close button: the
    /// start window comes back and asks whether to quit. The close cannot be stopped on visionOS,
    /// so the game keeps running until the answer.
    func tableDidDisappear() {
        guard root.gameModel.gameConfig.state != .stopped, !model.isEndingGame else { return }
        model.asksToQuit = true
        showStartWindowIfNeeded()
    }

    /// Opens the start window only when it is not on screen. The start window is a window group
    /// that can have several windows, and `ScenesManager.openWindow(_:)` asks SwiftUI again for a
    /// window that is already open (to raise it): that opened a second start window next to the
    /// one that asked "Quit Game?", so after Quit the main window had to be closed twice.
    private func showStartWindowIfNeeded() {
        switch scenesManager.getSceneState(for: SceneId.game) {
        case .closed, .closing: scenesManager.openWindow(SceneId.game)
        case .opening, .opened: break
        }
    }

    /// The start window went away with no table open: nothing of the game is left on screen to
    /// return to, so the game ends.
    func launchWindowDidDisappear() async {
        guard root.gameModel.gameConfig.state == .started, !model.isEndingGame, !model.isOpening,
              !model.asksToQuit else { return }
        switch scenesManager.getSceneState(for: SceneId.gameTable) {
        case .closed, .closing: await endGame()
        case .opening, .opened: break
        }
    }

    private func openGameWindow() {
        let config = root.gameModel.gameConfig
        if config.isMaster {
            guard let adventureId = config.master.adventureId else { return }
            scenesManager.openWindow(
                SceneId.viewerId(for: .adventure),
                selection: WindowItemSelection(itemId: adventureId)
            )
        } else if let characterId = root.gameModel.selectedCharacter {
            scenesManager.openWindow(
                SceneId.viewerId(for: .value),
                selection: WindowItemSelection(itemId: characterId)
            )
        }
    }
}
#endif
