// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct MinimumRow: View {
    let itemId: UUID

    @Environment(ValueRoot.self) private var root
    
    var body: some View {
        @Bindable var model = root.itemController.itemOrEmpty(for: itemId) 
        VStack {
            if let photoId = model.photoId {
                root.photoRoot.viewController.thumbnailView(with: photoId)
            }

            Text(model.name)
        }
    }
}

#Preview {
    MinimumRow(itemId: ValueModel.previewId)
        .environment(ValueRoot.preview)
}

