// @copyright André Trettin

import CoreRPG
import SwiftUI
import PhotoRPG

struct MinimumRow: View {
    let itemId: UUID

    @Environment(AdventureRootModel.self) private var root
    
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
        .environment(AdventureRootModel.preview)
}

