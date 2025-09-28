// @copyright André Trettin

import CoreRPG
import DiceRPG
import SwiftUI

struct OverlayGameLayout<MenuTab: View, Side: View, ToolBar: View>: View {
    let root: GameRootController
    let hideDice: Bool
    let menuOverlay: () -> MenuTab
    let sideOverlay: () -> Side
    let toolBarOverlay: () -> ToolBar
    
    @Environment(GameScreenModel.self) private var gameScreenModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: valueFor(iOS: 4, macOS: 4, tvOS: 12, visionOS: 4)) {
#if !os(visionOS)
                openDiceButtonView
#endif
                menuOverlay()
            }
            .zIndex(1)
            
            HStack {
                sideOverlay()
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .overlay(alignment: .topLeading) {
#if !os(visionOS)
                if gameScreenModel.showDice {
                    diceOverlay
                        .transition(.move(edge: .leading))
                }
#endif
            }
            .overlay(alignment: .bottomLeading) {
                toolBarOverlay()
                    .padding(.bottom, valueFor(iOS: 0, macOS: 12, tvOS: 0, visionOS: 0))
            }
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

private extension OverlayGameLayout {
    @ViewBuilder
    var openDiceButtonView: some View {
        if hideDice {
            EmptyView()
        } else {
            Button {
                withAnimation { gameScreenModel.showDice.toggle() }
            } label: {
                Image(systemName: "bag\(gameScreenModel.showDice ? ".fill" : "")")
                    .contentTransition(.symbolEffect(.replace.wholeSymbol))
            }
#if !os(tvOS)
            .buttonStyle(.borderedProminent)
#endif
        }
    }
    
    var diceOverlay: some View {
        //root.diceRoot.viewController.overlayGameView(hideDice: hideDice)
        Text("")
    }
}

//#Preview(traits: .defaultLayout) {
//    ZStack {
//        Color.brown
//            .ignoresSafeArea()
//        
//        OverlayGameLayout(root: .preview, hideDice: false) {
//            HStack {
//                Spacer()
//                Button { } label: {
//                    Image(systemName: "xmark")
//                }
//#if !os(tvOS)
//                .buttonStyle(.borderedProminent)
//#endif
//            }
//        } sideOverlay: {
//            Color.red
//                .frame(width: 200)
//        } toolBarOverlay: {
//            Button { } label: {
//                Image(systemName: "eraser")
//            }
//#if !os(tvOS)
//            .buttonStyle(.borderedProminent)
//#endif
//        }
//        .environment(GameScreenModel())
//        .environment(DiceDisplayModel())
//    }
//}
//
//
