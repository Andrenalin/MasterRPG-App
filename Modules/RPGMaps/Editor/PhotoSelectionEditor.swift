// @copyright André Trettin

import AndrenalinKit
import SwiftUI
import RPGPhotos

struct PhotoSelectionEditor: View {
    let editController: EditController

    @Environment(MapRoot.self) private var root
    
    var body: some View {
        root.photoRoot.viewController.photoSelection(root: root.photoRoot, editController: editController, selectionModel: editController.mapEditModel.photoSelectionModel)
            .onChange(of: editController.mapEditModel.photoSelectionModel.currentValue) {
                guard editController.mapEditModel.photoSelectionModel.currentValue != editController.model.photoId else { return }
                Task {
                    if let itemId = editController.mapEditModel.photoSelectionModel.currentValue {
                        await editController.toggle(for: .photo, itemRowModel: ItemRowModel(itemId: itemId, typeId: .photo))
                    } else {
                        editController.model.photoId = nil
                    }
                }
            }
    }
}
