// @copyright André Trettin

import AndrenalinKit
import SwiftUI
import RPGPhotos

struct MinimumRow: View {
    let itemId: UUID

    @Environment(AdventureRoot.self) private var root
    
    var body: some View {
        @Bindable var model = model
        VStack {
            if let photoId = model.photoId {
                root.photoRoot.viewController.thumbnailView(root: root.photoRoot, with: photoId)
            }

            Text(model.name)
        }
    }

    private var model: AdventureModel {
        root.itemController.itemOrEmpty(for: itemId)
    }
}

#Preview {
    MinimumRow(itemId: AdventureModel.previewId)
        .environment(AdventureRoot.preview)
}

