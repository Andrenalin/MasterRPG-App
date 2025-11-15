// @copyright André Trettin

import AndrenalinKit
import SwiftUI
import RPGDie

struct EntryListDiceRow: View {
    let itemId: UUID
    let entryId: UUID

    @Environment(ValueRoot.self) private var root
    @State private var updateOtherValue: Bool = false

    var body: some View {
        @Bindable var model = root.itemController.itemOrEmpty(for: itemId)
        if let id = root.gameController.gameDiceId(itemId: itemId, entryId: entryId) {
            root.diceRoot.viewController.viewDice(root: root.diceRoot, with: id, for: ResultCategory(id: itemId, childId: entryId, module: root.itemController.itemDataModel.networkModule), onlyPrimaryAction: true)
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
        withAnimation { root.diceRoot.diceGameControllable.validateForValue(diceId: id, compareValue: diceValue) }
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
        .environment(ValueRoot.preview)
}
