// @copyright André Trettin

import CoreRPG
import DiceRPG
import SwiftUI

struct OverlayGameLayout<MenuTab: View, Side: View, ToolBar: View>: View {
    let root: GameRoot
    let hideDice: Bool
    let menuOverlay: () -> MenuTab
    let sideOverlay: () -> Side
    let toolBarOverlay: () -> ToolBar
    
    @Environment(GameScreenModel.self) private var gameScreenModel
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    
    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()

        Group {
#if os(macOS)
            OverlayGameSideContent(
                side: sideOverlay(),
                toolbar: toolBarOverlay(),
                dice: root.diceRoot.viewController.overlayGameView(root: root.diceRoot, hideDice: hideDice),
                showsDice: gameScreenModel.showDice
            )
#else
            VStack(alignment: .leading, spacing: 8) {
                menuOverlay()
                    .zIndex(1)

                OverlayGameSideContent(
                    side: sideOverlay(),
                    toolbar: toolBarOverlay(),
                    dice: root.diceRoot.viewController.overlayGameView(root: root.diceRoot, hideDice: hideDice),
                    showsDice: gameScreenModel.showDice
                )
            }
#endif
        }
        .padding(.horizontal, 4)
        .padding(.trailing, valueFor(iOS: 0, macOS: 0, tvOS: 0, visionOS: 20))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .animation(accessibilityReduceMotion ? nil : .bouncy, value: gameScreenModel.showDice)
        .onAppear {
            guard hideDice == false && !gameScreenModel.showDice else { return }
            gameScreenModel.showDice.toggle()
        }
    }
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
