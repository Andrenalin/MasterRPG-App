// @copyright André Trettin

import CoreRPG
import DiceRPG
import SwiftUI

struct DetailEditorView: View {
    let root: TableRootModel
    let model: TableModel

    var body: some View {
        DetailSelectionEditorView(root: root, model: model)
            .onChange(of: model.id, initial: true) {
                root.editController.editorModel.sheetRootModel?.reset(itemId: model.id)
            }

        if let sheetRootModel = root.editController.editorModel.sheetRootModel {
            SheetRootEditorView(
                root: root.rootController,
                sheetRootModel: sheetRootModel,
                headerTitle: String(localized: "Entries", bundle: .module).localizedString,
                linkTypes: LinkTableModuleTransferable.self
            )
        }
    }
}

struct DetailSelectionEditorView: View {
    let root: TableRootModel
    let model: TableModel

    var body: some View {
        root.diceRoot.viewController.dropChooseView(model: root.editController.tableEditModel.selectionDice)
            .onChange(of: root.editController.tableEditModel.selectionDice.selection) {
                withAnimation(.easeInOut) { root.editController.add(diceId: root.editController.tableEditModel.selectionDice.itemId, itemId: model.id) }
            }
            .task(id: model.diceId) {
                root.editController.tableEditModel.selectionDice.resetSelection(itemId: model.diceId, entryId: nil)
            }
    }
}
