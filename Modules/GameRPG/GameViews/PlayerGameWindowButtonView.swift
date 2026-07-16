// @copyright André Trettin

#if os(visionOS) || os(macOS)
import CoreRPG
import SwiftUI

struct PlayerGameWindowButtonView: View {
    let root: GameRoot

    @Environment(AppSettingsModel.self) private var appSettingsModel
    @Environment(GameScreenModel.self) private var gameScreenModel
    @Environment(ScenesManager.self) private var scenesManager
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    var body: some View {
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
        .disabled(root.gameModel.selectedCharacter == nil && !isWindowPresented)
    }

    private var gameWindowScene: SceneId {
        SceneId.viewerId(for: .value)
    }

    private func toggleGameWindow(isPresented: Bool) {
        if isPresented {
            scenesManager.dismissWindow(gameWindowScene)
            gameScreenModel.gameMainTabDisplayMode = .hidden
            appSettingsModel.playerMainTabDisplayMode = GameMainTabDisplayMode.hidden.rawValue
        } else if let characterId = root.gameModel.selectedCharacter {
            withAnimation(accessibilityReduceMotion ? nil : .default) {
                gameScreenModel.showMainTab = .none
                gameScreenModel.gameMainTabDisplayMode = .window
            }
            appSettingsModel.playerMainTabDisplayMode = GameMainTabDisplayMode.window.rawValue
            scenesManager.openWindow(
                gameWindowScene,
                selection: WindowItemSelection(itemId: characterId)
            )
        }
    }
}

#Preview(traits: .mockData) {
    PlayerGameWindowButtonView(root: .previewFixture(game: .player))
        .environment(GameScreenModel())
}
#endif
