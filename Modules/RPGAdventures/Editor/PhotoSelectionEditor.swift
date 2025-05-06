// @copyright André Trettin

import AndrenalinKit
import SwiftUI
import RPGPhotos

struct PhotoSelectionEditor: View {
    let editController: EditController

    @Environment(AdventureRoot.self) private var root
    
    var body: some View {
        root.photoRoot.viewController.photoSelection(editController: editController, selectionModel: editController.adventureEditModel.photoSelectionModel)
            .onChange(of: editController.adventureEditModel.photoSelectionModel.currentValue) {
                guard editController.adventureEditModel.photoSelectionModel.currentValue != editController.model.photoId else { return }
                Task {
                    if let itemId = editController.adventureEditModel.photoSelectionModel.currentValue {
                        await editController.toggle(for: .photo, itemRowModel: ItemRowModel(itemId: itemId, typeId: .photo))
                    } else {
                        editController.model.photoId = nil
                    }
                }
            }
    }
}
