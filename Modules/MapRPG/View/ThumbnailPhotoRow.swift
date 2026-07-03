// @copyright André Trettin

import CoreRPG
import PhotoRPG
import SwiftUI

struct ThumbnailPhotoRow: View, Equatable {
    let itemId: UUID
    var item: MapModel? = nil

    @Environment(MapRootModel.self) private var root

    var body: some View {
        if let photoId = model?.photoId {
            root.photoRoot.viewController.thumbnailRow(root: root.photoRoot, for: photoId, listDisplayModel: root.listDisplayModel)
        }
    }

    private var model: MapModel? {
        item ?? root.itemController.itemSync(for: itemId)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.itemId == rhs.itemId && lhs.item == rhs.item
    }
}

#Preview(traits: .mockData) {
    ThumbnailPhotoRow(itemId: MockData.previewId)
}
