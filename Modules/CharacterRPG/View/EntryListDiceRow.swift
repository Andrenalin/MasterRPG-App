// @copyright André Trettin

import CoreRPG
import SwiftUI
import DiceRPG

struct EntryListDiceRow: View {
    let itemId: UUID
    let entryId: UUID

    @Environment(CharacterRootModel.self) private var root
    @State private var updateOtherValue: Bool = false
    @State private var isFavorited: Bool = false

    var body: some View {
        @Bindable var model = root.itemController.itemOrEmpty(for: itemId)
        if let id = root.gameController.gameDiceId(itemId: itemId, entryId: entryId) {
            HStack {
                Button {
                    // Toggle favorite with game dice ID and entry name
                    root.diceRoot.diceGameControllable.toggleFavoriteDice(itemId: id, diceName: model[entryId].name)
                    // Update local state to trigger UI refresh
                    isFavorited = root.diceRoot.diceGameControllable.isFavoriteDice(itemId: id)
                } label: {
                    Image(systemName: isFavorited ? "star.fill" : "star")
                }
                .contentShape(.rect)
                
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
            }
            .task(id: id) {
                isFavorited = root.diceRoot.diceGameControllable.isFavoriteDice(itemId: id)
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
        .environment(CharacterRootModel.preview)
}
