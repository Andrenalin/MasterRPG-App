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
            .modifier(AdaptToPhotoSizeDialog(root: root, editModel: root.editController.mapEditModel))
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

    func body(content: Content) -> some View {
        content.confirmationDialog(
            Text("Adapt Rooms and Pins?", bundle: .module),
            isPresented: Binding(
                get: { editModel.photoReplacement != nil },
                set: { if !$0 { editModel.photoReplacement = nil } }
            ),
            titleVisibility: .visible,
            presenting: editModel.photoReplacement
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
        } message: { _ in
            Text("The new photo has a different size than the current map. Resize the rooms and move the pins to match it, or keep them at their current positions?", bundle: .module)
        }
    }
}

#Preview(traits: .mockData) {
    DetailSelectionEditorView(root: .preview, model: .preview)
}
