// @copyright André Trettin

import CoreRPG
import PhotoRPG
import SwiftUI

struct PhotoDropSection: View {
    let root: CharacterRootModel
    let model: ValueModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()

        root.photoRoot.viewController.carouselPhotos(root: root.photoRoot, photoSelection: root.editController.valueEditModel.selectionPhoto)
            .onChange(of: root.editController.valueEditModel.selectionPhoto.selection) {
                withAnimation(reduceMotion ? nil : .easeInOut) {
                    root.editController.add(selection: root.editController.valueEditModel.selectionPhoto.selection, itemId: model.id)
                }
            }
            .task(id: model.photoId) {
                root.editController.valueEditModel.selectionPhoto.resetSelection(selectionIds: model.editorPhotos)
            }
    }
}

#Preview(traits: .mockData) {
    PhotoDropSection(root: .preview, model: .preview)
}
