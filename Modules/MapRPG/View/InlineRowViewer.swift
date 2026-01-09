// @copyright André Trettin

import CoreRPG
import DiceRPG
import PdfRPG
import PhotoRPG
import SwiftUI
import AudioRPG

struct InlineRowViewer: View, Equatable {
    let source: ItemRowModel
    let destination: ItemRowModel
    
    @Environment(MapRootModel.self) private var root
    
    var body: some View {
        switch source.typeId {
        case .audio:
            root.audioRoot.viewController.rowViewer(source: source, destination: destination)
        case .dice:
            root.diceRoot.viewController.rowViewer(source: source, destination: destination)
        case .pdf:
            root.pdfRoot.viewController.rowViewer(source: source, destination: destination)
        case .photo:
            root.photoRoot.viewController.photoRow(root: root.photoRoot, for: source.itemId)
        case .map:
            if let cacheController = root.cacheController {
                ThumbnailRowPhotoView(cacheController: cacheController, model: model, entryId: source.entryId)
                    .environment(root.editController.cacheItemListModel)
                    .environment(root.listDisplayModel)
            }
        default:
            EmptyView()
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
