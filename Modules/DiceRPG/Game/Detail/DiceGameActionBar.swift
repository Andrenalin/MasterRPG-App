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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    var body: some View {
        GlassEffectContainerAll {
            HStack(spacing: 8) {
                if !root.gameController.isPlayerDice(itemId: itemId) {
                    if !hideOwnDice {
                        Button {
                        withAnimation(Animation.default.reduced(if: reduceMotion)) {
                            diceDisplayModel.isEditing.toggle()
                        }
                        } label: {
                        Label {
                            if diceDisplayModel.isEditing {
                                Text("Finish editing dice", bundle: .module)
                            } else {
                                Text("Edit dice", bundle: .module)
                            }
                        } icon: {
                            Image(systemName: "square.and.pencil\(diceDisplayModel.isEditing ? ".fill" : "")")
                                .contentTransition(.symbolEffect(.replace.wholeSymbol))
                        }
                        .labelStyle(.iconOnly)
                        .frame(minWidth: 44, minHeight: 44)
                        }
                        .gameOverlayControlStyle(isSelected: diceDisplayModel.isEditing)
                        .disabled(!root.gameController.canEditDice(itemId: itemId, isGameMode: appGameStateModel.isGameRunning))
                        .opacity(root.gameController.canEditDice(itemId: itemId, isGameMode: appGameStateModel.isGameRunning) ? 1 : 0.5)
                        // A roll mutates `.dice` (results/rotation), never
                        // `.entries` (a separate child-reference field) — this
                        // previously watched a property a roll never changes,
                        // so the compare-value haptic never fired. See
                        // CODE_AUDIT §5.6.
                        .onChange(of: root.gameController.gameItem(for: itemId).dice) {
                            diceRollResult = root.gameController.result(itemId: itemId).checked
                        }
#if !os(visionOS)
                        .sensoryFeedback(diceRollResult ? .success : .error, trigger: diceRollResult)
#endif
                    
                    Button {
                        if diceDisplayModel.isEditing {
                            withAnimation(Animation.default.reduced(if: reduceMotion)) {
                                diceDisplayModel.isEditing = false
                            }
                        }
                        withAnimation(Animation.default.reduced(if: reduceMotion)) {
                            root.gameController.rollDice(itemId: itemId, networkActions: networkActions)
                        }
                    } label: {
                        Label {
                            Text("Roll dice", bundle: .module)
                        } icon: {
                            Image(systemName: diceIcon)
                                .contentTransition(.symbolEffect(.replace.wholeSymbol))
                        }
                        .labelStyle(.iconOnly)
                        .frame(minWidth: 44, minHeight: 44)
                    }
                    .gameOverlayControlStyle()
                }

                if canShowPlayer {
                    if !root.gameController.diceGameModel.playerDice.isEmpty {
                        Button {
                            withAnimation(Animation.default.reduced(if: reduceMotion)) {
                                diceDisplayModel.showPlayerDice.toggle()
                            }
                        } label: {
                            Label {
                                if diceDisplayModel.showPlayerDice {
                                    Text("Hide player dice", bundle: .module)
                                } else {
                                    Text("Show player dice", bundle: .module)
                                }
                            } icon: {
                                Image(systemName: "person.2")
                            }
                            .labelStyle(.iconOnly)
                            .frame(minWidth: 44, minHeight: 44)
                        }
                        .gameOverlayControlStyle(isSelected: diceDisplayModel.showPlayerDice)
                    }
                }
                
                if appGameStateModel.gameModus == .player && root.gameController.gameModel.focusItemIds.count > 1 {
                    Button {
                        if let last = root.gameController.gameModel.focusItemIds.last {
                            withAnimation(Animation.default.reduced(if: reduceMotion)) {
                                root.gameController.gameModel.focusItemIds = [last]
                            }
                        }
                    } label: {
                        Label {
                            Text("Show focused dice", bundle: .module)
                        } icon: {
                            Image(systemName: "switch.2")
                        }
                        .labelStyle(.iconOnly)
                        .frame(minWidth: 44, minHeight: 44)
                    }
                    .gameOverlayControlStyle()

                }
                if showFocusButton && !root.gameController.isFocusedDice(itemId: itemId) {
                    Spacer()

                    Button {
                        withAnimation(Animation.default.reduced(if: reduceMotion)) {
                            root.gameController.gameModel.focusItemIds = [itemId]
                        }
                    } label: {
                        Label {
                            Text("Set as focused dice", bundle: .module)
                        } icon: {
                            Image(systemName: "house")
                        }
                        .labelStyle(.iconOnly)
                        .frame(minWidth: 44, minHeight: 44)
                    }
                    .gameOverlayControlStyle()
                }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    var diceIcon: String {
        root.gameController.hasResults(itemId: itemId) ? root.itemController.config.module.icon + ".fill" : root.itemController.config.module.icon
    }
}

#Preview(traits: .mockData) {
    ZStack {
        Color.black
        
        DiceGameActionBar(itemId: DiceModel.previewId, showFocusButton: true, canShowPlayer: true, hideOwnDice: false)

    }
}
