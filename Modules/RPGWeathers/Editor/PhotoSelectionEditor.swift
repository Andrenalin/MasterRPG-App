// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct PhotoSelectionEditor: View {
    let editController: EditController

    @Environment(WeatherRoot.self) private var root
    
    var body: some View {
        let _ = Self._printChanges()
        root.photoRoot.viewController.photoSelection(editController: editController, selectionModel: editController.weatherEditModel.photoSelectionModel)
            .onChange(of: editController.weatherEditModel.photoSelectionModel.currentValue) {
                guard editController.weatherEditModel.photoSelectionModel.currentValue != editController.model.photoId else { return }
                Task {
                    if let itemId = editController.weatherEditModel.photoSelectionModel.currentValue {
                        await editController.toggle(for: .photo, itemRowModel: ItemRowModel(itemId: itemId, typeId: .photo))
                    } else {
                        editController.model.photoId = nil
                    }
                }
            }
    }
}
