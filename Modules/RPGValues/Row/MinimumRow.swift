// @copyright André Trettin

import AndrenalinKit
import SwiftUI
import PhotoRPG

struct MinimumRow: View {
    let itemId: UUID

    @Environment(CharacterRootModel.self) private var root
    
    var body: some View {
        @Bindable var model = root.itemController.itemOrEmpty(for: itemId) 
        VStack {
            if let photoId = model.photoId {
                root.photoRoot.viewController.thumbnailView(root: root.photoRoot, with: photoId)
            }

            Text(model.name)
        }
    }
}

#Preview {
    MinimumRow(itemId: ValueModel.previewId)
        .environment(CharacterRootModel.preview)
}

