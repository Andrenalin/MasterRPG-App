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
        .animation(.bouncy, value: gameScreenModel.showDice)
        .onAppear {
            guard hideDice == false && !gameScreenModel.showDice else { return }
            gameScreenModel.showDice.toggle()
        }
    }
}

private struct OverlayGameSideContent<Side: View, ToolBar: View, Dice: View>: View {
    let side: Side
    let toolbar: ToolBar
    let dice: Dice
    let showsDice: Bool

    var body: some View {
        HStack {
            side
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        .overlay(alignment: .topLeading) {
#if !os(visionOS)
            if showsDice {
                dice
                    .transition(.move(edge: .leading))
            }
#endif
        }
        .overlay(alignment: .bottomLeading) {
            toolbar
                .padding(.bottom, valueFor(iOS: 0, macOS: 12, tvOS: 0, visionOS: 0))
        }
    }
}

struct GameDiceToggleButton: View {
    @Environment(GameScreenModel.self) private var gameScreenModel

    var body: some View {
        Button {
            withAnimation {
                gameScreenModel.showDice.toggle()
            }
        } label: {
            Label {
                Text(gameScreenModel.showDice ? "Hide Dice" : "Show Dice", bundle: .module)
            } icon: {
                Image(systemName: "bag\(gameScreenModel.showDice ? ".fill" : "")")
                    .contentTransition(.symbolEffect(.replace.wholeSymbol))
            }
            .labelStyle(.iconOnly)
        }
        .help(Text(gameScreenModel.showDice ? "Hide Dice" : "Show Dice", bundle: .module))
    }
}

#Preview(traits: .defaultLayout) {
    ZStack {
        Color.brown
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
            Color.red
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
    }
}
