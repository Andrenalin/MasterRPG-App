// @copyright André Trettin

import CoreRPG
import SwiftUI
import DiceRPG

struct EntryListDiceRow: View, Equatable {
    let itemId: UUID
    let entryId: UUID

    static func == (lhs: EntryListDiceRow, rhs: EntryListDiceRow) -> Bool {
        lhs.itemId == rhs.itemId && lhs.entryId == rhs.entryId
    }

    @Environment(CharacterRootModel.self) private var root
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let id = root.gameController.gameDiceId(itemId: itemId, entryId: entryId) {
            // Read in `body` (not in a manually re-armed `withObservationTracking`) so
            // SwiftUI re-evaluates this row whenever any entry the formula links to
            // changes — at any depth and for any number of links — and pushes the new
            // value into the game dice, which re-counts its dice via `addDiceEvery`.
            let compareValue = root.linkController.diceCompareValue(itemId: itemId, entryId: entryId)
            root.diceRoot.viewController.viewDice(root: root.diceRoot, with: id, for: ResultCategory(id: itemId, childId: entryId, module: root.itemController.config.module), player: true)
                .onChange(of: compareValue, initial: true) {
                    updateDiceValue(id: id, compareValue: compareValue)
                }
                .onChange(of: id) {
                    updateDiceValue(id: id, compareValue: compareValue)
                }
        } else {
            EmptyView()
        }
    }

    private func updateDiceValue(id: UUID, compareValue: Int?) {
        withAnimation(reduceMotion ? nil : .default) {
            root.diceRoot.diceGameControllable.validateForValue(diceId: id, compareValue: compareValue)
        }
    }
}

#Preview {
    EntryListDiceRow(itemId: ValueModel.previewId, entryId: UUID())
        .environment(CharacterRootModel.preview)
}
