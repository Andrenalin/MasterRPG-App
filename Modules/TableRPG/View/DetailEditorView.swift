// @copyright André Trettin

import CoreRPG
import DiceRPG
import SwiftUI

struct DetailEditorView: View {
    let root: TableRootModel
    let model: TableModel

    @State private var sheetRootModel: SheetRootModel?

    var body: some View {
        DetailSelectionEditorView(root: root, model: model)
            .task(id: model.id) {
                sheetRootModel = SheetRootModel(
                    linkControllable: root.rootController.linkControllable,
                    sheetControllable: root.rootController.sheetControllable,
                    itemId: model.id,
                    isEditor: true,
                    editorModel: root.editController.sheetEditorModel
                )
            }

        if let sheetRootModel {
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
