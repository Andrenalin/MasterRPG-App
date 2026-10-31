// @copyright André Trettin

import CoreRPG
import PhotoRPG
import SwiftUI

struct DetailSelectionEditorView: View {
    let root: MapRootModel
    let model: MapModel

    /// The photo the user picked; `.task(id:)` replaces it, so a newer pick or leaving the view cancels the work.
    @State private var pickedPhoto: PickedPhoto?

    var body: some View {
        root.photoRoot.viewController.dropSelectionView(model: root.editController.mapEditModel.selectionPhoto)
            .onChange(of: root.editController.mapEditModel.selectionPhoto.itemId) {
                pickedPhoto = PickedPhoto(photoId: root.editController.mapEditModel.selectionPhoto.itemId)
            }
            .task(id: pickedPhoto) {
                guard let pickedPhoto else { return }
                await root.editController.replacePhoto(photoId: pickedPhoto.photoId, itemId: model.id)
                self.pickedPhoto = nil
            }
            .modifier(AdaptToPhotoSizeDialog(root: root, editModel: root.editController.mapEditModel, mapId: model.id))
            .task(id: model.photoId) {
                root.editController.mapEditModel.selectionPhoto.resetSelection(
                    itemId: model.photoId,
                    entryId: nil
                )
            }
    }
}

private struct PickedPhoto: Equatable {
    let photoId: UUID?
}

/// Asks whether rooms and pins follow a new photo of another size.
private struct AdaptToPhotoSizeDialog: ViewModifier {
    let root: MapRootModel
    @Bindable var editModel: MapEditModel
    let mapId: UUID

    /// The pending replacement of this map. The model is shared by all maps, so another map's
    /// pending choice must not show here.
    private var replacement: PhotoReplacement? {
        editModel.photoReplacement.flatMap { $0.itemId == mapId ? $0 : nil }
    }

    func body(content: Content) -> some View {
        content.confirmationDialog(
            Text("Adapt Rooms and Pins?", bundle: .module),
            isPresented: Binding(
                get: { replacement != nil },
                set: { isPresented in
                    // Dismissed without a button (outside the iPad popover, Esc): the same as
                    // Cancel, so the picker shows the map's photo again. After Adapt or Keep the
                    // replacement is already gone; a reset to the old photo there is corrected by
                    // the picker's `.task(id: model.photoId)`. See CODE_AUDIT_Since_3.0.1 §5.11.
                    guard !isPresented, let replacement else { return }
                    root.editController.cancel(replacement)
                }
            ),
            titleVisibility: .visible,
            presenting: replacement
        ) { replacement in
            Button {
                withAnimation { root.editController.apply(replacement, adaptContent: true) }
            } label: {
                Text("Adapt to New Size", bundle: .module)
            }
            Button {
                withAnimation { root.editController.apply(replacement, adaptContent: false) }
            } label: {
                Text("Keep Positions", bundle: .module)
            }
            Button(role: .cancel) {
                root.editController.cancel(replacement)
            } label: {
                Text("Cancel", bundle: .module)
            }
        } message: { replacement in
            if replacement.changesAspectRatio {
                // Rooms are scaled per axis, so another shape stretches them. See CODE_AUDIT_Since_3.0.1 §5.10.
                Text("The new photo has a different size and shape than the current map. Adapting stretches the rooms and moves the pins to match it, and a hex grid is created again. Or keep them at their current positions?", bundle: .module)
            } else {
                Text("The new photo has a different size than the current map. Resize the rooms and move the pins to match it, or keep them at their current positions?", bundle: .module)
            }
        }
    }
}

#Preview(traits: .mockData) {
    DetailSelectionEditorView(root: .preview, model: .preview)
}
