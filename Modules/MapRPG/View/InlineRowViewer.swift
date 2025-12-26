// @copyright André Trettin

import CoreRPG
import PhotoRPG
import SwiftUI

struct InlineRowViewer: View, Equatable {
    let source: ItemRowModel
    
    @Environment(MapRootModel.self) private var root
    
    var body: some View {
        if source.typeId == .photo {
            root.photoRoot.viewController.photoRow(root: root.photoRoot, for: source.itemId)
        }
        if source.typeId == .map, let cacheController = root.cacheController {
            ThumbnailRowPhotoView(cacheController: cacheController, model: model, entryId: source.entryId)
                .environment(root.editController.cacheItemListModel)
                .environment(root.listDisplayModel)
        }
    }
    
    var model: MapModel {
        root.itemController.itemOrEmpty(for: source.itemId)
    }
    
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.source == rhs.source
    }
}

#Preview(traits: .mockData) {
    InlineRowViewer(source: ItemRowModel(itemId: MockData.previewId, typeId: .photo))
}
