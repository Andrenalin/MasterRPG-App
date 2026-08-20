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
        .disabled(root.gameModel.selectedCharacter == nil && !isWindowPresented)
    }

    private var gameWindowScene: SceneId {
        GameWindowToggle.sceneId(isMaster: false)
    }

    private func toggleGameWindow(isPresented: Bool) {
        if isPresented {
            GameWindowToggle.close(
                isMaster: false,
                scenesManager: scenesManager,
                gameScreenModel: gameScreenModel,
                appSettingsModel: appSettingsModel
            )
        } else {
            GameWindowToggle.open(
                isMaster: false,
                itemId: root.gameModel.selectedCharacter,
                scenesManager: scenesManager,
                gameScreenModel: gameScreenModel,
                appSettingsModel: appSettingsModel,
                animated: !accessibilityReduceMotion
            )
        }
    }
}

#Preview(traits: .mockData) {
    PlayerGameWindowButtonView(root: .previewFixture(game: .player))
        .environment(GameScreenModel())
}
#endif
