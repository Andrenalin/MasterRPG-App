// @copyright André Trettin

import CoreRPG
import DiceRPG
import SwiftUI

struct DiceDropSection: View {
    let root: CharacterRootModel
    let model: ValueModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()

        root.diceRoot.viewController.dropChooseView(model: root.editController.valueEditModel.selectionDice)
            .onChange(of: root.editController.valueEditModel.selectionDice.selection) {
                withAnimation(reduceMotion ? nil : .easeInOut) {
                    // The editor persists also during a game.
                    root.editController.add(diceId: root.editController.valueEditModel.selectionDice.itemId, itemId: model.id, forceSave: true)
                }
            }
            .task(id: model.diceId) {
                root.editController.valueEditModel.selectionDice.resetSelection(itemId: model.diceId, entryId: nil)
            }
    }
}

#Preview(traits: .mockData) {
    DiceDropSection(root: .preview, model: .preview)
}
