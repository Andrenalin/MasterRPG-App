// @copyright André Trettin

import CoreRPG
import SwiftUI

struct DiceGameActionBar: View {
    let itemId: UUID
    let showFocusButton: Bool
    let canShowPlayer: Bool
    let hideOwnDice: Bool

    @State private var diceRollResult: Bool = false
    
    @Environment(DiceRootModel.self) private var root
    @Environment(DiceDisplayModel.self) var diceDisplayModel
    
    @Environment(AppGameStateModel.self) private var appGameStateModel
    @Environment(\.networkActions) private var networkActions
    
    var body: some View {
        HStack(spacing: 8) {
            if !root.gameController.isPlayerDice(itemId: itemId) {
                
                if !hideOwnDice {
                    Button { withAnimation { diceDisplayModel.isEditing.toggle() } } label: {
                        Image(systemName: "square.and.pencil.circle\(diceDisplayModel.isEditing ? ".fill" : "")")
                            .contentTransition(.symbolEffect(.replace.wholeSymbol))
                            .frame(height: 24)
                    }
#if !os(tvOS)
                    .buttonStyle(.borderedProminent)
#endif
                    .disabled(!root.gameController.canEditDice(itemId: itemId, isGameMode: appGameStateModel.isGameRunning))
                    .opacity(root.gameController.canEditDice(itemId: itemId, isGameMode: appGameStateModel.isGameRunning) ? 1 : 0.5)
                    .onChange(of: root.gameController.gameItem(for: itemId).entries) {
                        diceRollResult = root.gameController.result(itemId: itemId).checked
                    }
#if !os(visionOS)
                    .sensoryFeedback(diceRollResult ? .success : .error, trigger: diceRollResult)
#endif
                    
                    Button {
                        if diceDisplayModel.isEditing {
                            withAnimation { diceDisplayModel.isEditing = false }
                        }
                        withAnimation { root.gameController.rollDice(itemId: itemId, networkActions: networkActions) }
                    } label: {
                        Image(systemName: diceIcon)
                            .contentTransition(.symbolEffect(.replace.wholeSymbol))
                            .frame(height: 24)
                    }
#if !os(tvOS)
                    .buttonStyle(.borderedProminent)
#endif
                }

                if canShowPlayer {
                    if !root.gameController.diceGameModel.playerDice.isEmpty {
                        Button { withAnimation { diceDisplayModel.showPlayerDice.toggle() } } label: {
                            Image(systemName: "person.2")
                                .frame(height: 24)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                
                if appGameStateModel.gameModus == .player && root.gameController.gameModel.focusItemIds.count > 1 {
                    Button {
                        if let last = root.gameController.gameModel.focusItemIds.last {
                            withAnimation { root.gameController.gameModel.focusItemIds = [last] }
                        }
                    } label: {
                        Image(systemName: "switch.2")
                            .frame(height: 24)
                    }
#if !os(tvOS)
                    .buttonStyle(.borderedProminent)
#endif

                }
                if showFocusButton && !root.gameController.isFocusedDice(itemId: itemId) {
                    Spacer()

                    Button { withAnimation { root.gameController.gameModel.focusItemIds = [itemId] } } label: {
                        Image(systemName: "house")
                            .frame(height: 24)
                    }
#if !os(tvOS)
                    .buttonStyle(.borderedProminent)
#endif
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    var diceIcon: String {
        root.gameController.hasResults(itemId: itemId) ? root.itemController.config.module.icon + ".fill" : root.itemController.config.module.icon
    }
}

#Preview {
    DiceGameActionBar(itemId: DiceModel.previewId, showFocusButton: true, canShowPlayer: false, hideOwnDice: true)
        .environment(DiceRootModel.preview)
        .environment(DiceDisplayModel())
}
