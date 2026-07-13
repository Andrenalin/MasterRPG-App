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
            // task is swallowing the updates later, this causes a 2 double creation on start / that is acceptable
            .onChange(of: model.id, initial: true) {
                root.editorLinkModel.characterSelectionModel.onlyChildrenFrom <=> model.id
                root.editController.editorModel.sheetRootModel?.reset(itemId: model.id)
            }

        if let rootModel = root.editController.editorModel.sheetRootModel {
            SheetRootEditorView(
                root: root.rootController,
                sheetRootModel: rootModel,
                headerTitle: String(localized: "Values", bundle: .module).localizedString,
                linkTypes: LinkCharacterModuleTransferable.self
            )
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

#Preview(traits: .mockData) { DetailEditorView(root: .preview, model: .preview) }
#Preview(traits: .mockData) { DetailSelectionEditorView(root: .preview, model: .preview) }
#Preview(traits: .mockData) { DiceDropSection(root: .preview, model: .preview) }
#Preview(traits: .mockData) { PhotoDropSection(root: .preview, model: .preview) }
