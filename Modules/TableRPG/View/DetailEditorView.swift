// @copyright André Trettin

import CoreRPG
import DiceRPG
import SwiftUI

struct DetailEditorView: View {
    let root: TableRootModel
    let model: TableModel

    var body: some View {
        DetailSelectionEditorView(root: root, model: model)
        
        SheetRootEditorView(
            root: root.rootController,
            linkControllable: root.linkControllable,
            editorModel: root.editController.sheetEditorModel,
            model: model,
            module: root.config.module,
            headerTitle: String(localized: "Entries", bundle: .module).localizedString,
            linkTypes: LinkTableModuleTransferable.self
        )
    }
}

struct DetailSelectionEditorView: View {
    let root: TableRootModel
    let model: TableModel

    var body: some View {
        root.diceRoot.viewController.dropChooseView(model: root.editController.tableEditModel.selectionDice)
            .onChange(of: root.editController.tableEditModel.selectionDice.selection) {
                withAnimation { root.editController.add(diceId: root.editController.tableEditModel.selectionDice.itemId, itemId: model.id) }
            }
            .task(id: model.diceId) {
                root.editController.tableEditModel.selectionDice.resetSelection(itemId: model.diceId, entryId: nil)
            }
    }
}
