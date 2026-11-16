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
    @Environment(\.quickDiceSlots) private var quickDiceSlots
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // The game dice is created in the task below, never while `body` runs: creating it
        // writes observable state this body reads. See CODE_AUDIT_26 §8.2.
        let entry = root.gameController.gameItem(for: itemId)[entryId]
        let templateDiceId = entry.supportsDice ? entry.diceId : nil
        Group {
            if templateDiceId == nil {
                EmptyView()
            } else {
                content
            }
        }
        .task(id: templateDiceId) {
            root.gameController.ensureGameDice(itemId: itemId, entryId: entryId)
        }
    }

    @ViewBuilder
    private var content: some View {
        if let id = root.gameController.gameDiceId(itemId: itemId, entryId: entryId) {
            // Read in `body` (not in a manually re-armed `withObservationTracking`) so
            // SwiftUI re-evaluates this row whenever any entry the formula links to
            // changes — at any depth and for any number of links — and pushes the new
            // value into the game dice, which re-counts its dice via `addDiceEvery`.
            let linkedValue = root.linkController.diceCompareValue(itemId: itemId, entryId: entryId)
            // A quick dice slot holding this entry shares the dice; a value typed over it there
            // stays in force here, until the entry's own value changes.
            let compareValue = quickDiceSlots?.effectiveValue(linkedValue: linkedValue, forItem: itemId, entry: entryId) ?? linkedValue
            HStack(spacing: 4) {
                root.diceRoot.viewController.viewDice(root: root.diceRoot, with: id, for: ResultCategory(id: itemId, childId: entryId, module: root.itemController.config.module), player: true)
                QuickDiceFavoriteMenu(itemId: itemId, entryId: entryId)
            }
                .onChange(of: compareValue, initial: true) {
                    updateDiceValue(id: id, compareValue: compareValue)
                }
                .onChange(of: id) {
                    updateDiceValue(id: id, compareValue: compareValue)
                }
        } else {
            // A modifier on an `EmptyView` has no view to attach to, so the `.task` above would
            // never run and the game dice would never be created. This zero-size view hosts it
            // until the dice exists.
            Color.clear
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
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
