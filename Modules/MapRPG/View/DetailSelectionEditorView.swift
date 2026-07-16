// @copyright André Trettin

import CoreRPG
import PhotoRPG
import SwiftUI

struct DetailSelectionEditorView: View {
    let root: MapRootModel
    let model: MapModel

    var body: some View {
        root.photoRoot.viewController.dropSelectionView(model: root.editController.mapEditModel.selectionPhoto)
            .onChange(of: root.editController.mapEditModel.selectionPhoto.itemId) {
                withAnimation {
                    root.editController.add(
                        photoId: root.editController.mapEditModel.selectionPhoto.itemId,
                        itemId: model.id
                    )
                }
            }
            .task(id: model.photoId) {
                root.editController.mapEditModel.selectionPhoto.resetSelection(
                    itemId: model.photoId,
                    entryId: nil
                )
            }
    }
}

#Preview(traits: .mockData) {
    DetailSelectionEditorView(root: .preview, model: .preview)
}
