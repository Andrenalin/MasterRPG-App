// @copyright André Trettin

import CoreRPG
import SwiftUI

struct OpenPhotoWorldSpace: View {
    let editController: EditController
    let itemId: UUID

    @Environment(PhotoRootModel.self) private var root

#if os(visionOS)
    @Environment(\.openImmersiveSpace) private var openSpace
    @Environment(\.dismissImmersiveSpace) private var dismissSpace
#endif
    
    @State private var hasOpenSpace: Bool = false
    
    var body: some View {
        @Bindable var model = root.gameController.photoGameModel
        
#if os(visionOS)
        Toggle(isOn: $model.openPhotoSpace) {
            Label { Text("Show image in the world space", bundle: .module) } icon: { Image(systemName: "globe") }
        }
        .tint(Color.accentColor)
        .onChange(of: model.openPhotoSpace, initial: true) {
            Task {
                if model.openPhotoSpace {
                    await openSpace(id: "PhotoWorld", value: root.gameController.photoGameModel.currentSelection)
                } else {
                    await dismissSpace()
                }
            }
        }
        .onChange(of: editController.sheetEditorModel.itemId, initial: true) {
            guard let itemId = editController.sheetEditorModel.itemId else { return }
            Task {
                _ = await root.gameController.setCurrent(itemId: itemId)
                root.gameController.photoGameModel.currentSelection = PhotoWorldSelection(id: itemId, rotationDegrees: 67)
            }
        }
#endif
    }
}

#Preview {
    OpenPhotoWorldSpace(editController: .preview, itemId: PhotoModel.previewId)
        .environment(PhotoRootModel.preview)
}
