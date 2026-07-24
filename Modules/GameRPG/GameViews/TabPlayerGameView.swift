// @copyright André Trettin

import CharacterRPG
import CoreRPG
import SwiftUI

struct TabPlayerGameView: View {
    let root: GameRoot

    @Environment(GameScreenModel.self) private var gameScreenModel
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        if root.gameModel.gameType != .observer {
            NavigationStack {
                if let characterId = root.gameModel.selectedCharacter {
                    root.characterRoot.viewController.gameView(
                        root: root.characterRoot,
                        select: characterId,
                        inlineSearch: usesInlineSearch
                    )
                }
            }
            .frame(
                maxWidth: gameScreenModel.sideBarWidth,
                maxHeight: .infinity,
                alignment: valueFor(iOS: .trailing, macOS: .trailing, tvOS: .trailing, visionOS: .leading)
            )
#if os(iOS)
            .ignoresSafeArea(.container, edges: .bottom)
            .clipShape(.rect(topLeadingRadius: 14, topTrailingRadius: 14))
#endif
#if !os(visionOS)
            .background(.ultraThinMaterial, in: .rect(cornerRadius: 14))
#endif
            .offset(
                x: gameScreenModel.showMainTab == .none
                    ? valueFor(
                        iOS: gameScreenModel.sideBarWidth,
                        macOS: gameScreenModel.sideBarWidth,
                        tvOS: gameScreenModel.sideBarWidth,
                        visionOS: -gameScreenModel.sideBarWidth
                    )
                    : 0
            )
            .opacity(gameScreenModel.showMainTab == .none ? 0 : 1)
            .allowsHitTesting(gameScreenModel.showMainTab != .none)
            .accessibilityHidden(gameScreenModel.showMainTab == .none)
            .shadow(radius: 8)
            .animation(accessibilityReduceMotion ? nil : .bouncy, value: gameScreenModel.showMainTab)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { width in
                gameScreenModel.updateInlineMainOverlayWidth(width)
            }
        }
    }

    private var usesInlineSearch: Bool {
#if os(iOS) || os(macOS)
        true
#else
        false
#endif
    }
}

#Preview {
    TabPlayerGameView(root: .previewFixture(game: .player))
        .environment(GameScreenModel())
}
