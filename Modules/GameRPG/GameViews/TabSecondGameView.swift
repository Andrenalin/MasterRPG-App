// @copyright André Trettin

import AdventureRPG
import CoreRPG
import SwiftUI

struct TabSecondGameView: View {
    let root: GameRoot

    @Environment(GameScreenModel.self) private var gameScreenModel
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        NavigationStack {
            root.adventureRoot.viewController.gameModuleListView(root: root.adventureRoot, isPlayer: false)
                .navigationVisibility(true)
        }
            .frame(
                maxWidth: gameScreenModel.sideBarWidth,
                maxHeight: .infinity,
                alignment: valueFor(iOS: .trailing, macOS: .trailing, tvOS: .trailing, visionOS: .leading)
            )
#if os(iOS)
            .ignoresSafeArea()
            .clipShape(.rect(
                topLeadingRadius: 14,
                bottomLeadingRadius: 14,
                bottomTrailingRadius: 0,
                topTrailingRadius: 0
            ))
            .background(.ultraThinMaterial, in: .rect(
                topLeadingRadius: 14,
                bottomLeadingRadius: 14,
                bottomTrailingRadius: 0,
                topTrailingRadius: 0
            ))
#elseif !os(visionOS)
            .background(.ultraThinMaterial, in: .rect(cornerRadius: 14))
#endif
            .offset(
                x: gameScreenModel.showSettingTab == .none
                    ? valueFor(
                        iOS: gameScreenModel.sideBarWidth,
                        macOS: gameScreenModel.sideBarWidth,
                        tvOS: gameScreenModel.sideBarWidth,
                        visionOS: -gameScreenModel.sideBarWidth
                    )
                    : 0
            )
            .opacity(gameScreenModel.showSettingTab == .none ? 0 : 1)
            .allowsHitTesting(gameScreenModel.showSettingTab != .none)
            .accessibilityHidden(gameScreenModel.showSettingTab == .none)
            .shadow(radius: 8)
            .animation(accessibilityReduceMotion ? nil : .bouncy, value: gameScreenModel.showSettingTab)
    }
}

#Preview {
    TabSecondGameView(root: .previewFixture())
        .environment(GameScreenModel())
}
