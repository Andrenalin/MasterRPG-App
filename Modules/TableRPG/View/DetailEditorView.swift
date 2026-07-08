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
            .onChange(of: model.id, initial: true) {
                if sheetRootModel == nil {
                    let rootController = root.rootController
                    guard let rootManager = rootController.rootManager else { return }

                    sheetRootModel = SheetRootModel(
                        rootManager: rootManager,
                        linkControllable: rootController.linkControllable,
                        sheetControllable: rootController.sheetControllable,
                        itemId: model.id,
                        isEditor: true,
                        editorModel: root.editController.editorModel.sheetEditorModel
                    )
                } else {
                    sheetRootModel?.reset(itemId: model.id)
                }
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
