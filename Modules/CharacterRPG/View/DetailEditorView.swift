// @copyright André Trettin

import CoreRPG
import DiceRPG
import PhotoRPG
import SwiftUI

struct DetailEditorView: View {
    let root: CharacterRootModel
    let model: ValueModel

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        
        DetailSelectionEditorView(root: root, model: model)

        SheetRootEditorView(
            root: root.rootController,
            linkControllable: root.linkControllable,
            editorModel: root.editController.sheetEditorModel,
            model: model,
            module: root.config.module,
            headerTitle: String(localized: "Values", bundle: .module).localizedString,
            linkTypes: LinkCharacterModuleTransferable.self
        )
        .task(id: model.id) {
            root.editorLinkModel.characterSelectionModel.onlyChildrenFrom <=> model.id
        }
    }
}

struct DetailSelectionEditorView: View {
    let root: CharacterRootModel
    let model: ValueModel

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        
        DiceDropSection(root: root, model: model)
        PhotoDropSection(root: root, model: model)
    }
}

private struct DiceDropSection: View {
    let root: CharacterRootModel
    let model: ValueModel

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        
        root.diceRoot.viewController.dropChooseView(model: root.editController.valueEditModel.selectionDice)
            .onChange(of: root.editController.valueEditModel.selectionDice.selection) {
                withAnimation(.easeInOut) {
                    root.editController.add(diceId: root.editController.valueEditModel.selectionDice.itemId, itemId: model.id)
                }
            }
            .task(id: model.diceId) {
                root.editController.valueEditModel.selectionDice.resetSelection(itemId: model.diceId, entryId: nil)
            }
    }
}

private struct PhotoDropSection: View {
    let root: CharacterRootModel
    let model: ValueModel

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        
        root.photoRoot.viewController.carouselPhotos(root: root.photoRoot, photoSelection: root.editController.valueEditModel.selectionPhoto)
            .onChange(of: root.editController.valueEditModel.selectionPhoto.selection) {
                withAnimation(.easeInOut) {
                    root.editController.add(selection: root.editController.valueEditModel.selectionPhoto.selection, itemId: model.id)
                }
            }
            .task(id: model.photoId) {
                root.editController.valueEditModel.selectionPhoto.resetSelection(selectionIds: model.photos)
            }
    }
}
