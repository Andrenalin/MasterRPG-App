// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct MinimumRow: View {
    let itemId: UUID

    @Environment(AdventureRoot.self) private var root
    
    var body: some View {
        @Bindable var model = model
        VStack {
            if let photoId = model.photoId {
                root.photoRoot.viewController.thumbnailView(with: photoId)
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

