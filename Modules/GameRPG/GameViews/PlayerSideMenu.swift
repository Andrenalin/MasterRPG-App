// @copyright André Trettin

#if os(visionOS) || os(macOS)
import CoreRPG
import SwiftUI

struct PlayerSideMenu: View {
    let root: GameRoot

    private static let modules: [NetworkModules] = [
        .value,
        .table,
        .audio,
        .photo,
        .pdf,
        .space,
        .dice
    ]

    var body: some View {
        GlassEffectContainerAll {
            VStack(spacing: 8) {
                if root.gameModel.gameType != .observer {
                    PlayerGameWindowButtonView(root: root)
                }

                ForEach(Self.modules, id: \.self) { module in
                    GameWindowButtonView(
                        title: module.title,
                        systemImage: module.icon,
                        tint: module.tint,
                        sceneId: SceneId.sceneId(for: module)
                    )
                }
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
