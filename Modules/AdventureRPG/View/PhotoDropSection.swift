// @copyright André Trettin

import CoreRPG
import PhotoRPG
import SwiftUI

struct PhotoDropSection: View {
    let root: AdventureRootModel
    let model: AdventureModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        root.photoRoot.viewController.dropSelectionView(model: root.editController.adventureEditModel.selectionPhoto)
            .onChange(of: root.editController.adventureEditModel.selectionPhoto.itemId) {
                withAnimation(reduceMotion ? nil : .easeInOut) {
                    // The editor persists also during a game.
                    root.editController.add(photoId: root.editController.adventureEditModel.selectionPhoto.itemId, itemId: model.id, forceSave: true)
                }
            }
            .task(id: model.photoId) {
                root.editController.adventureEditModel.selectionPhoto.resetSelection(itemId: model.photoId, entryId: nil)
            }
    }
}

#Preview(traits: .mockData) {
    PhotoDropSection(root: .preview, model: .preview)
}
