// @copyright André Trettin

import CoreRPG
import DiceRPG
import PhotoRPG
import SwiftUI

struct InlineRowViewer: View, Equatable {
    let source: ItemRowModel
    let destination: ItemRowModel
    
    @Environment(MapRootModel.self) private var root
    
    var body: some View {
        switch source.typeId {
        case .dice:
            root.diceRoot.viewController.rowViewer(source: source, destination: destination)
        case .photo:
            root.photoRoot.viewController.photoRow(root: root.photoRoot, for: source.itemId)
        default:
            if source.typeId == root.config.module, let cacheController = root.cacheController {
                ThumbnailRowPhotoView(cacheController: cacheController, model: model, entryId: source.entryId)
                    .environment(root.editController.cacheItemListModel)
                    .environment(root.listDisplayModel)
            }
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
    InlineRowViewer(source: ItemRowModel(itemId: MockData.previewId, typeId: .photo), destination: ItemRowModel(itemId: UUID(), entryId: nil, typeId: .table))
}
