// @copyright André Trettin

import CoreRPG
import SwiftUI

struct InlineRowViewer: View, Equatable {
    let source: ItemRowModel
    let destination: ItemRowModel
    
    @Environment(PdfRootModel.self) private var root
    
    @Environment(ScenesManager.self) private var scenesManager
    @Environment(\.navigator) private var navigator


    var body: some View {
        if let cacheController = root.cacheController {
            HStack {
                if source.entryId == nil {
                    ThumbnailRowPhotoView(cacheController: cacheController, model: model, listDisplayModel: root.listDisplayModel, entryId: source.entryId)
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
        scenesManager.openWindow(SceneId(rawValue: root.configurable.module.viewerWindowId), selection: WindowItemSelection(itemId: destination.itemId, entryId: destination.entryId))
#else
        navigator.navigate(to: DetailRoute.viewer(destination.itemId, destination.entryId), method: .managedSheet)
#endif
    }
}

#Preview(traits: .mockData) {
    InlineRowViewer(source: ItemRowModel(itemId: MockData.previewId, typeId: .pdf), destination: ItemRowModel(itemId: UUID(), entryId: nil, typeId: .table))
}
