// @copyright André Trettin

import CoreRPG
import PhotoRPG
import SwiftData
import SwiftUI

struct ThumbnailDiceRow: View {
    let itemId: UUID
    
    @Environment(MapRootModel.self) private var root
    
    var body: some View {
        let _ = Self._printChanges()
        if let photoId = model?.photoId {
            root.photoRoot.viewController.thumbnailRow(root: root.photoRoot, for: photoId)
        }
    }
    
    private var model: MapDataModel? {
        root.itemController.model(for: itemId)
    }
}

#Preview(traits: .mockData) {
    ThumbnailDiceRow(itemId: MockData.previewId)
}
