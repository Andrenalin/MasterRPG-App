// @copyright André Trettin

import AndrenalinKit
import SwiftUI
import PhotoRPG

struct PhotoSelectionEditor: View {
    let editController: EditController

    @Environment(CharacterRootModel.self) private var root

    var body: some View {
        let _ = Self._printChanges()
        @Bindable var model = editController.model
        root.photoRoot.viewController.photosSelection(root: root.photoRoot, editController: editController, model: $model.photos, selected: $model.photoId, filter: .value) {
            Button {
                Task {
                    await editController.setGroupPhotos()
                }
            } label: {
                Label {
                    Text("Set photos on all subgroups", bundle: .module)
                } icon: {
                    Image(systemName: "square.on.square.squareshape.controlhandles")
                }
            }
            .padding(.top, valueFor(iOS: 0, macOS: 12, tvOS: 0, visionOS: 0))
        } selection: {
            model.photos.map { ItemRowModel(itemId: $0, typeId: .photo) }
        } toggleSelection: { selected, _ in
            if let index = model.photos.firstIndex(of: selected.itemId) {
                model.photos.remove(at: index)
            } else {
                model.photos.append(selected.itemId)
            }
        }
    }
}
