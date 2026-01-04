// @copyright André Trettin

import CoreRPG
import SwiftUI

struct InlineRowViewer: View, Equatable {
    let source: ItemRowModel
    
    @Environment(PdfRootModel.self) private var root
    
    var body: some View {
        if source.typeId == root.config.module, let cacheController = root.cacheController {
            ThumbnailRowPhotoView(cacheController: cacheController, model: model, entryId: source.entryId)
                .environment(root.editController.cacheItemListModel)
                .environment(root.listDisplayModel)
        }
    }
    
    var model: PdfModel {
        root.itemController.itemOrEmpty(for: source.itemId)
    }
    
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.source == rhs.source
    }
}

#Preview(traits: .mockData) {
    InlineRowViewer(source: ItemRowModel(itemId: MockData.previewId, typeId: .pdf))
}
