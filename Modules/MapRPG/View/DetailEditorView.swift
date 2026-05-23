// @copyright André Trettin

import CoreRPG
import PhotoRPG
import SwiftUI

struct DetailEditorView: View {
    let root: MapRootModel
    let model: MapModel
    
    var body: some View {
        DetailSelectionEditorView(root: root, model: model)
        
        DisplayConfigEditor(model: model)
        
        SheetRootEditorView(root: root.rootController, linkControllable: root.linkControllable, editorModel: root.editController.sheetEditorModel, model: model, module: root.config.module, headerTitle: String(localized: "Rooms", bundle: .module).localizedString, linkTypes: LinkMapModuleTransferable.self)
    }
}

struct DetailSelectionEditorView: View {
    let root: MapRootModel
    let model: MapModel
    
    var body: some View {
        root.photoRoot.viewController.dropSelectionView(model: root.editController.mapEditModel.selectionPhoto)
            .onChange(of: root.editController.mapEditModel.selectionPhoto.itemId) {
                withAnimation { root.editController.add(photoId: root.editController.mapEditModel.selectionPhoto.itemId, itemId: model.id) }
            }
            .task(id: model.photoId) {
                root.editController.mapEditModel.selectionPhoto.resetSelection(itemId: model.photoId, entryId: nil)
            }
    }
}
