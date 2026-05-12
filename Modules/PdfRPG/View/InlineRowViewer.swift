// @copyright André Trettin

import CoreRPG
import SwiftUI

struct InlineRowViewer: View, Equatable {
    let source: ItemRowModel
    let destination: ItemRowModel
    
    @Environment(PdfRootModel.self) private var root
    
#if !os(tvOS)
    @Environment(\.openWindow) private var openWindow
#endif
    @Environment(\.navigator) private var navigator


    var body: some View {
        if let cacheController = root.cacheController {
            HStack {
                if source.entryId == nil {
                    ThumbnailRowPhotoView(cacheController: cacheController, model: model, entryId: source.entryId)
                        .environment(root.editController.cacheItemListModel)
                        .environment(root.listDisplayModel)
                }
                Button {
                    actionHandler()
                } label: {
                    Image(systemName: root.configurable.module.icon)
                        .imageScale(.large)
                }
                .font(source.entryId == nil ? .largeTitle : .default)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }
    
    var model: PdfModel {
        root.itemController.itemOrEmpty(for: source.itemId)
    }
    
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.source == rhs.source
    }
    
    private func actionHandler() {
#if os(visionOS) || os(macOS)
        openWindow(id: root.configurable.module.viewerWindowId, value: WindowItemSelection(itemId: destination.itemId, entryId: destination.entryId))
#else
        navigator.navigate(to: DetailRoute.viewer(destination.itemId, destination.entryId), method: .managedSheet)
#endif
    }
}

#Preview(traits: .mockData) {
    InlineRowViewer(source: ItemRowModel(itemId: MockData.previewId, typeId: .pdf), destination: ItemRowModel(itemId: UUID(), entryId: nil, typeId: .table))
}
