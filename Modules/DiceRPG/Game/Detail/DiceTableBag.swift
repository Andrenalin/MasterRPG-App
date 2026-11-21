// @copyright André Trettin

import CoreRPG
import SwiftUI

/// The 3D table's dice edit mode, as small views for its popovers: the button that enters it, the
/// dice bag that stands over the dice in it, and the button over each die that removes it.
/// `DiceDisplayModel.isEditing` is the mode, as on the 2D screens.

/// Enters the dice edit mode (the dice result popover's button). Not offered for dice that cannot
/// be edited: another player's shared dice and a table's dice in a running game.
struct DiceTableEditButton: View {
    @Environment(DiceRootModel.self) private var root
    @Environment(DiceDisplayModel.self) private var diceDisplayModel
    @Environment(AppGameStateModel.self) private var appGameStateModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        FocusedDiceContainer { itemId in
            if !root.gameController.isPlayerDice(itemId: itemId),
               root.gameController.canEditDice(itemId: itemId, isGameMode: appGameStateModel.isGameRunning) {
                Button {
                    withAnimation(Animation.default.reduced(if: reduceMotion)) {
                        diceDisplayModel.isEditing = true
                    }
                } label: {
                    Label {
                        Text("Edit dice", bundle: .module)
                    } icon: {
                        Image(systemName: "square.and.pencil")
                    }
                    .labelStyle(.iconOnly)
                }
                .gameOverlayControlStyle()
            }
        }
    }
}

/// The dice bag in the dice edit mode: only the kinds the table can show (`supportedSides`),
/// each with how many of them the focused set holds out of the table's pool (`poolSize` per
/// kind). Tapping adds a die to the focused set, which then lies in the seat's row; a kind whose
/// pool is used up, or a set that cannot be edited, is disabled. The button to its left closes
/// the bag and returns to the roll mode, the roll button next to it does that and rolls.
struct DiceTableBag: View {
    let supportedSides: Set<Int>
    let poolSize: Int

    @Environment(DiceRootModel.self) private var root
    @Environment(DiceDisplayModel.self) private var diceDisplayModel
    @Environment(AppGameStateModel.self) private var appGameStateModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        FocusedDiceContainer { itemId in
            let item = root.gameController.gameItem(for: itemId)
            let canEdit = root.gameController.canEditDice(itemId: itemId, isGameMode: appGameStateModel.isGameRunning)
                && !root.gameController.isPlayerDice(itemId: itemId)
            HStack(spacing: 8) {
                Button {
                    withAnimation(Animation.default.reduced(if: reduceMotion)) {
                        diceDisplayModel.isEditing = false
                    }
                } label: {
                    Label {
                        Text("Finish editing dice", bundle: .module)
                    } icon: {
                        Image(systemName: "checkmark")
                    }
                    .labelStyle(.iconOnly)
                }
                .gameOverlayControlStyle(isSelected: true)

                ForEach(root.itemController.diceBag.dice.filter { supportedSides.contains($0.die.max) }) { die in
                    let used = item.dice.count { $0.die.max == die.die.max }
                    Button {
                        withAnimation(Animation.default.reduced(if: reduceMotion)) {
                            item.dice.append(DieModel(id: UUID(), die: die.die))
                        }
                    } label: {
                        VStack(spacing: 2) {
                            DieViewerView(gameController: root.gameController, diceId: UUID(), die: die, withoutResult: true, resultColor: [])
                            Text(verbatim: "\(used)/\(poolSize)")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .padding(4)
                    }
                    .accessibilityLabel(Text("Add \(die.die.text) die", bundle: .module))
                    .frame(minWidth: 44, minHeight: 44)
                    .disabled(!canEdit || used >= poolSize)
                }

                // Closes the edit mode itself, and rolls the dice with the ones just added.
                DiceRollButton(itemId: itemId)
            }
        }
    }
}

/// The button over one die of the focused set in the dice edit mode: removes it.
struct DiceTableRemoveButton: View {
    /// The die's index in the focused set.
    let setIndex: Int

    @Environment(DiceRootModel.self) private var root
    @Environment(AppGameStateModel.self) private var appGameStateModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let itemId = root.gameController.gameModel.focusItemIds.first {
            let dice = root.gameController.gameItem(for: itemId).dice
            if dice.indices.contains(setIndex),
               root.gameController.canEditDice(itemId: itemId, isGameMode: appGameStateModel.isGameRunning) {
                let die = dice[setIndex]
                Button {
                    withAnimation(Animation.default.reduced(if: reduceMotion)) {
                        root.gameController.remove(die: die, from: itemId)
                    }
                } label: {
                    Label {
                        Text("Remove \(die.die.text) die", bundle: .module)
                    } icon: {
                        Image(systemName: "x.circle.fill")
                    }
                    .labelStyle(.iconOnly)
                }
                .gameOverlayControlStyle(tint: .red)
            }
        }
    }
}

#Preview {
    DiceTableBag(supportedSides: [4, 6, 8, 10, 12, 20], poolSize: 6)
        .environment(DiceRootModel.previewWithData)
        .environment(DiceDisplayModel())
}
