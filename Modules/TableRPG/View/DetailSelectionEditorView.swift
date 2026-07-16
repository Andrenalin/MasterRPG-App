// @copyright André Trettin

import CoreRPG
import DiceRPG
import SwiftUI

struct DetailSelectionEditorView: View {
    let root: TableRootModel
    let model: TableModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        root.diceRoot.viewController.dropChooseView(
            model: root.editController.tableEditModel.selectionDice
        )
        .onChange(of: root.editController.tableEditModel.selectionDice.selection) {
            withAnimation(reduceMotion ? nil : .easeInOut) {
                root.editController.add(
                    diceId: root.editController.tableEditModel.selectionDice.itemId,
                    itemId: model.id
                )
            }
        }
        .task(id: model.diceId) {
            root.editController.tableEditModel.selectionDice.resetSelection(
                itemId: model.diceId,
                entryId: nil
            )
        }
    }
}

#Preview(traits: .mockData) {
    DetailSelectionEditorView(root: .preview, model: .preview)
}
