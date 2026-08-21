// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftUI

/// The master's floating adventure window toggle, or the player's floating character
/// sheet window toggle — merged behind `isMaster` since the two views only differed in
/// which item id backs the window and whether the button disables itself when no item
/// is selected yet. Previously `MasterGameWindowButtonView`/`PlayerGameWindowButtonView`,
/// two ~90%-identical files. See CODE_AUDIT §9.6.
struct GameWindowMenuButtonView: View {
    let isMaster: Bool
    /// The adventure id for the master (always available by the time a caller shows
    /// this button) or the player's currently selected character id (`nil` when no
    /// character is selected yet, in which case the button disables rather than
    /// no-opping the tap — matches `PlayerGameWindowButtonView`'s original guard).
    let itemId: UUID?

    @Environment(AppSettingsModel.self) private var appSettingsModel
    @Environment(GameScreenModel.self) private var gameScreenModel
    @Environment(ScenesManager.self) private var scenesManager
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        let isWindowPresented = scenesManager.getSceneState(for: gameWindowScene).isPresentedInGameMenu

        Button {
            toggleGameWindow(isPresented: isWindowPresented)
        } label: {
            Label {
                Text(NetworkModules.game.localizedTitle)
            } icon: {
                Image(systemName: NetworkModules.game.icon)
            }
        }
        .labelStyle(.iconOnly)
        .imageScale(.large)
        .padding(8)
        .contentShape(.circle)
        .modifier(
            GameWindowButtonAppearance(
                module: .game,
                isWindowPresented: isWindowPresented
            )
        )
        .help(NetworkModules.game.title)
        .accessibilityValue(
            Text(isWindowPresented ? "Window open" : "Window closed", bundle: .module)
        )
        .disabled(itemId == nil && !isWindowPresented)
    }

    private var gameWindowScene: SceneId {
        GameWindowToggle.sceneId(isMaster: isMaster)
    }

    private func toggleGameWindow(isPresented: Bool) {
        if isPresented {
            GameWindowToggle.close(
                isMaster: isMaster,
                scenesManager: scenesManager,
                gameScreenModel: gameScreenModel,
                appSettingsModel: appSettingsModel
            )
        } else {
            GameWindowToggle.open(
                isMaster: isMaster,
                itemId: itemId,
                scenesManager: scenesManager,
                gameScreenModel: gameScreenModel,
                appSettingsModel: appSettingsModel,
                animated: !accessibilityReduceMotion
            )
        }
    }
}

#Preview("Master", traits: .mockData) {
    GameWindowMenuButtonView(isMaster: true, itemId: GamePreviewData.adventureID)
        .environment(GameScreenModel())
}

#Preview("Player", traits: .mockData) {
    GameWindowMenuButtonView(isMaster: false, itemId: nil)
        .environment(GameScreenModel())
}
