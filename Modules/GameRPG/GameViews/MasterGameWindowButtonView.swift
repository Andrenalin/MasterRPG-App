// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftUI

struct MasterGameWindowButtonView: View {
    let adventureId: UUID

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
                tint: NetworkModules.game.tint,
                isWindowPresented: isWindowPresented
            )
        )
        .help(NetworkModules.game.title)
        .accessibilityValue(
            Text(isWindowPresented ? "Window open" : "Window closed", bundle: .module)
        )
    }

    private var gameWindowScene: SceneId {
        SceneId.viewerId(for: .adventure)
    }

    private func toggleGameWindow(isPresented: Bool) {
        if isPresented {
            scenesManager.dismissWindow(gameWindowScene)
            gameScreenModel.gameMainTabDisplayMode = .hidden
            appSettingsModel.masterMainTabDisplayMode = GameMainTabDisplayMode.hidden.rawValue
        } else {
            withAnimation(accessibilityReduceMotion ? nil : .default) {
                gameScreenModel.showMainTab = .none
                gameScreenModel.gameMainTabDisplayMode = .window
            }
            appSettingsModel.masterMainTabDisplayMode = GameMainTabDisplayMode.window.rawValue
            scenesManager.openWindow(
                gameWindowScene,
                selection: WindowItemSelection(itemId: adventureId)
            )
        }
    }
}

#Preview(traits: .mockData) {
    MasterGameWindowButtonView(adventureId: GamePreviewData.adventureID)
        .environment(GameScreenModel())
}
