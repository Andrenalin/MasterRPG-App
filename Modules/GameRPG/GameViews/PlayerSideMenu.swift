// @copyright André Trettin

#if os(visionOS) || os(macOS)
import CoreRPG
import SwiftUI

struct PlayerSideMenu: View {
    let root: GameRoot

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        GlassEffectContainerAll {
            VStack(spacing: 8) {
                if root.gameModel.gameType != .observer {
                    GameWindowMenuButtonView(isMaster: false, itemId: root.gameModel.selectedCharacter)
                }

                ForEach(NetworkModules.gameWindowPlayerModules, id: \.self) { module in
                    GameWindowButtonView(
                        title: module.title,
                        systemImage: module.icon,
                        module: module,
                        sceneId: SceneId.sceneId(for: module)
                    )
                }
#if os(visionOS)
                // macOS has the button in the toolbar.
                if root.gameModel.gameType == .player {
                    TablePlayersButton(root: root)
                        .imageScale(.large)
                        .padding(8)
                        .contentShape(.circle)
                        .modifier(GameWindowButtonAppearance(module: .value, isWindowPresented: false))
                }
#endif
            }
        }
#if os(macOS)
        .padding(.trailing, 8)
#else
        .padding()
#endif
    }
}

#Preview(traits: .mockData) {
    PlayerSideMenu(root: .previewFixture(game: .player))
        .environment(GameScreenModel())
}
#endif
