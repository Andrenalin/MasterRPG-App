// @copyright André Trettin

import CoreRPG
import SwiftUI
import DiceRPG

struct EntryListDiceRow: View, Equatable {
    let itemId: UUID
    let entryId: UUID
    /// Pre-resolved by the caller where available — see `ViewControllable`'s
    /// doc comment / CODE_AUDIT_10 §8.1. Falls back to `itemOrEmpty` when
    /// nil, so this stays correct for any call site not yet updated.
    var resolvedModel: ValueModel? = nil

    /// Compares `resolvedModel` by identity (its `id`) rather than deep value equality —
    /// it's a resolved reference, not owned row content. See CODE_AUDIT §8.6.
    static func == (lhs: EntryListDiceRow, rhs: EntryListDiceRow) -> Bool {
        lhs.itemId == rhs.itemId
            && lhs.entryId == rhs.entryId
            && lhs.resolvedModel?.id == rhs.resolvedModel?.id
    }

    @Environment(CharacterRootModel.self) private var root
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var updateOtherValue: Bool = false

    var body: some View {
        @Bindable var model = resolvedModel ?? root.itemController.itemOrEmpty(for: itemId)
        if let id = root.gameController.gameDiceId(itemId: itemId, entryId: entryId) {
            root.diceRoot.viewController.viewDice(root: root.diceRoot, with: id, for: ResultCategory(id: itemId, childId: entryId, module: root.itemController.config.module), player: true)
                .onChange(of: model[entryId].diceId, initial: false) {
                    updateDiceValue(id: id)
                }
                .onChange(of: model[entryId].value, initial: false) {
                    updateDiceValue(id: id)
                }
                .onChange(of: updateOtherValue, initial: true) {
                    updateDiceValue(id: id)
                    root.linkController.updateValueCalculation(itemId: model.id, entryId: entryId) {
                        updateOtherValue.toggle()
                    }
                }
        } else {
            EmptyView()
        }
    }

    private func updateDiceValue(id: UUID) {
        let diceValue = diceValue(itemId: itemId, entryId: entryId)
        withAnimation(reduceMotion ? nil : .default) {
            root.diceRoot.diceGameControllable.validateForValue(diceId: id, compareValue: diceValue)
        }
    }

    private func diceValue(itemId: UUID, entryId: UUID) -> Int? {
        let entry = root.itemController.itemOrEmpty(for: itemId)[entryId]
        guard entry.type == .number else { return nil }
        guard let valueText = root.linkController.calculate(entry: entry), let value = Int(valueText) else { return nil }
        return value
    }
}

#Preview {
    EntryListDiceRow(itemId: ValueModel.previewId, entryId: UUID())
        .environment(CharacterRootModel.preview)
}
