// @copyright André Trettin

import CoreRPG
import DiceRPG
import SwiftUI

struct OverlayGameLayout<MenuTab: View, Side: View, ModuleMenu: View, ToolBar: View>: View {
    let root: GameRoot
    let hideDice: Bool
    let menuOverlay: () -> MenuTab
    let sideOverlay: () -> Side
    let moduleMenuOverlay: () -> ModuleMenu
    let toolBarOverlay: () -> ToolBar

    init(
        root: GameRoot,
        hideDice: Bool,
        @ViewBuilder menuOverlay: @escaping () -> MenuTab,
        @ViewBuilder sideOverlay: @escaping () -> Side,
        @ViewBuilder moduleMenuOverlay: @escaping () -> ModuleMenu,
        @ViewBuilder toolBarOverlay: @escaping () -> ToolBar
    ) {
        self.root = root
        self.hideDice = hideDice
        self.menuOverlay = menuOverlay
        self.sideOverlay = sideOverlay
        self.moduleMenuOverlay = moduleMenuOverlay
        self.toolBarOverlay = toolBarOverlay
    }
    
    @Environment(GameScreenModel.self) private var gameScreenModel
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()

        ZStack(alignment: .topLeading) {
            sideOverlay()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
#if os(iOS)
                // The slot must touch the safe-area edges: with the chrome padding in
                // between, the panel's `ignoresSafeArea()` has no horizontal effect and
                // the panel stops short of the screen edge, while the navigation stack
                // inside it still insets its content by the full safe area.
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.safeAreaInsets.trailing
                } action: { trailingInset in
                    gameScreenModel.updateInlineSidebarTrailingOverhang(trailingInset + horizontalPadding)
                }
#else
                .padding(.horizontal, horizontalPadding)
#endif
                .zIndex(10)

            moduleMenuOverlay()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
#if os(iOS)
                .padding(.top, topContentInset)
#endif
                .padding(.horizontal, horizontalPadding)
                .zIndex(20)

#if !os(visionOS)
            if !hideDice && gameScreenModel.showDice {
                root.diceRoot.viewController.overlayGameView(root: root.diceRoot)
#if os(iOS)
                    // Dice and character/adventure content begin on the same
                    // row, one standard spacing step below the menu field.
                    .padding(.top, topContentInset)
#endif
                    .padding(.horizontal, horizontalPadding)
                    .transition(.move(edge: .leading))
                    .zIndex(30)
            }
#endif

            toolBarOverlay()
                .padding(.bottom, valueFor(iOS: 0, macOS: 12, tvOS: 0, visionOS: 0))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(.horizontal, horizontalPadding)
                .zIndex(40)

            menuOverlay()
#if os(iOS)
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { newHeight in
                    gameScreenModel.updateTopGameMenuHeight(newHeight)
                }
#endif
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.horizontal, horizontalPadding)
                .zIndex(50)
        }
        .padding(.trailing, valueFor(iOS: 0, macOS: 0, tvOS: 0, visionOS: 20))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .animation(accessibilityReduceMotion ? nil : .bouncy, value: gameScreenModel.showDice)
    }

    /// Applied per layer instead of to the whole stack, so the iOS side panel can reach
    /// the screen edge.
    private var horizontalPadding: CGFloat { 4 }

#if os(iOS)
    private var topContentInset: CGFloat {
        gameScreenModel.topGameMenuHeight + GameScreenModel.mapOverlaySpacing
    }
#endif
}

#Preview(traits: .defaultLayout) {
    ZStack {
        Rectangle().fill(Color.black.gradient)
            .ignoresSafeArea()
        
        OverlayGameLayout(root: .preview, hideDice: false) {
            HStack {
                Spacer()
                Button { } label: {
                    Image(systemName: "xmark")
                }
#if !os(tvOS)
                .buttonStyle(.borderedProminent)
#endif
            }
        } sideOverlay: {
            RoundedRectangle(cornerRadius: 16).fill(Color.red.gradient)
                .frame(width: 200)
        } moduleMenuOverlay: {
            EmptyView()
        } toolBarOverlay: {
            Button { } label: {
                Image(systemName: "eraser")
            }
#if !os(tvOS)
            .buttonStyle(.borderedProminent)
#endif
        }
        .environment(GameScreenModel())
        .environment(DiceDisplayModel())
        .environment(AppGameStateModel())
        .preferredColorScheme(.dark)
    }
}
