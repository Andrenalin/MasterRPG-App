// @copyright André Trettin

import CoreRPG
import DiceRPG
import PhotoRPG
import SwiftUI

struct DetailEditorView: View {
    let root: AdventureRootModel
    let model: AdventureModel

    var body: some View {
        DetailSelectionEditorView(root: root, model: model)
            .onChange(of: model.id, initial: true) {
                root.editController.editorModel.sheetRootModel?.reset(itemId: model.id)
            }

        if let rootModel = root.editController.editorModel.sheetRootModel {            
            SheetRootEditorView(
                root: root.rootController,
                sheetRootModel: rootModel,
                headerTitle: String(localized: "Sections", bundle: .module).localizedString,
                linkTypes: LinkAdventureModuleTransferable.self
            )
        }
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

#Preview(traits: .mockData) { DetailEditorView(root: .preview, model: .preview) }
#Preview(traits: .mockData) { DetailSelectionEditorView(root: .preview, model: .preview) }
#Preview(traits: .mockData) { DiceDropSection(root: .preview, model: .preview) }
#Preview(traits: .mockData) { PhotoDropSection(root: .preview, model: .preview) }
