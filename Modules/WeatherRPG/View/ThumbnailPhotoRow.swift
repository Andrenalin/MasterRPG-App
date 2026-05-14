// @copyright André Trettin

import CoreRPG
import PhotoRPG
import SwiftUI

struct ThumbnailPhotoRow: View, Equatable {
    let itemId: UUID
    
    @Environment(WeatherRootModel.self) private var root
    
    var body: some View {
        if let photoId = model?.photoId {
            root.photoRoot.viewController.thumbnailRow(root: root.photoRoot, for: photoId, listDisplayModel: root.listDisplayModel)
        }
    }
    
    private var model: WeatherModel? {
        root.itemController.itemSync(for: itemId)
    }
    
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.itemId == rhs.itemId
    }
}

#Preview(traits: .mockData) {
    ThumbnailPhotoRow(itemId: MockData.previewId)
}
