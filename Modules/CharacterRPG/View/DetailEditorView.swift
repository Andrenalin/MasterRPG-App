// @copyright André Trettin

import CoreRPG
import DiceRPG
import PhotoRPG
import SwiftUI

struct DetailEditorView: View {
    let root: CharacterRootModel
    let model: ValueModel
    
    var body: some View {
        root.diceRoot.viewController.dropChooseView(model: root.editController.valueEditModel.selectionDice)
            .onChange(of: root.editController.valueEditModel.selectionDice.selection) {
                withAnimation { root.editController.add(diceId: root.editController.valueEditModel.selectionDice.itemId, itemId: model.id) }
            }
            .task(id: model.diceId) {
                root.editController.valueEditModel.selectionDice.resetSelection(itemId: model.diceId, entryId: nil)
            }

        root.photoRoot.viewController.carouselPhotos(root: root.photoRoot, photoSelection: root.editController.valueEditModel.selectionPhoto)
            .onChange(of: root.editController.valueEditModel.selectionPhoto.selection) {
                withAnimation { root.editController.add(selection: root.editController.valueEditModel.selectionPhoto.selection, itemId: model.id) }
            }
            .task(id: model.photoId) {
                root.editController.valueEditModel.selectionPhoto.resetSelection(selectionIds: model.photos)
            }

        SheetRootEditorView(root: root.rootController, linkControllable: root.linkControllable, model: model, module: root.config.module, headerTitle: String(localized: "Values", bundle: .module).localizedString, linkTypes: LinkCharacterModuleTransferable.self)
            .task(id: model.id) {
                root.editController.setCurrentItem(to: ItemRowTreeModel(itemId: model.id, typeId: root.config.module))
                root.editorLinkModel.characterSelectionModel.onlyChildrenFrom <=> model.id
            }
            .id(model.id)
    }
}
