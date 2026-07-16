// @copyright André Trettin

import CoreRPG
import DiceRPG
import SwiftUI

struct DiceDropSection: View {
    let root: AdventureRootModel
    let model: AdventureModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        root.diceRoot.viewController.dropChooseView(model: root.editController.adventureEditModel.selectionDice)
            .onChange(of: root.editController.adventureEditModel.selectionDice.selection) {
                withAnimation(reduceMotion ? nil : .easeInOut) {
                    root.editController.add(diceId: root.editController.adventureEditModel.selectionDice.itemId, itemId: model.id)
                }
            }
            .task(id: model.diceId) {
                root.editController.adventureEditModel.selectionDice.resetSelection(itemId: model.diceId, entryId: nil)
            }
    }
}

#Preview(traits: .mockData) {
    DiceDropSection(root: .preview, model: .preview)
}
