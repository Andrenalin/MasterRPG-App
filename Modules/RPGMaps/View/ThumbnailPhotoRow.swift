// @copyright André Trettin

import AndrenalinKit
import PhotoRPG
import SwiftUI

struct ThumbnailPhotoRow: View {
    let itemId: UUID
    
    @Environment(MapRootModel.self) private var root
    
    var body: some View {
        let _ = Self._printChanges()
        if let photoId = model?.photoId {
            root.photoRoot.viewController.thumbnailRow(root: root.photoRoot, for: photoId)
        }
    }
    
    private var model: MapModel? {
        root.itemController.itemSync(for: itemId)
    }
}

#Preview(traits: .mockData) {
    ThumbnailPhotoRow(itemId: MockData.previewId)
}
