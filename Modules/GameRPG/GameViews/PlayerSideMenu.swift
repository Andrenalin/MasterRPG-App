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
                // The companions button is in the top ornament's menu; this one is the last window button.
                GameTableWindowButton(root: root, isMaster: false)
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
