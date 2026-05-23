// @copyright André Trettin

import CoreRPG
import SwiftUI
import DiceRPG
import PhotoRPG

struct DetailEditorView: View {
    let root: AdventureRootModel
    let model: AdventureModel

    var body: some View {
        DetailSelectionEditorView(root: root, model: model)

        SheetRootEditorView(
            root: root.rootController,
            linkControllable: root.linkControllable,
            editorModel: root.editController.sheetEditorModel,
            model: model,
            module: root.config.module,
            headerTitle: String(localized: "Sections", bundle: .module).localizedString,
            linkTypes: LinkAdventureModuleTransferable.self
        )
    }
}

struct DetailSelectionEditorView: View {
    let root: AdventureRootModel
    let model: AdventureModel

    var body: some View {
        DiceDropSection(root: root, model: model)
        PhotoDropSection(root: root, model: model)
    }
}

private struct DiceDropSection: View {
    let root: AdventureRootModel
    let model: AdventureModel

    var body: some View {
        root.diceRoot.viewController.dropChooseView(model: root.editController.adventureEditModel.selectionDice)
            .onChange(of: root.editController.adventureEditModel.selectionDice.selection) {
                withAnimation(.easeInOut) {
                    root.editController.add(diceId: root.editController.adventureEditModel.selectionDice.itemId, itemId: model.id)
                }
            }
            .task(id: model.diceId) {
                root.editController.adventureEditModel.selectionDice.resetSelection(itemId: model.diceId, entryId: nil)
            }
    }
}

private struct PhotoDropSection: View {
    let root: AdventureRootModel
    let model: AdventureModel

    var body: some View {
        root.photoRoot.viewController.dropSelectionView(model: root.editController.adventureEditModel.selectionPhoto)
            .onChange(of: root.editController.adventureEditModel.selectionPhoto.itemId) {
                withAnimation(.easeInOut) {
                    root.editController.add(photoId: root.editController.adventureEditModel.selectionPhoto.itemId, itemId: model.id)
                }
            }
            .task(id: model.photoId) {
                root.editController.adventureEditModel.selectionPhoto.resetSelection(itemId: model.photoId, entryId: nil)
            }
    }
}
