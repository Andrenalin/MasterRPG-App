// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI

struct MainRowView: View {
    let model: PhotoDataModel

    @Environment(CacheItemListModel.self) private var cacheModel
    @Environment(ListModel.self) private var listModel
    @Environment(SearchModel.self) private var searchModel
    @Environment(PhotoRootModel.self) private var root

    var body: some View {
        let _ = Self._printChanges()
        ItemRow(itemId: model.id, model: model, cacheItemListModel: cacheModel, name: \.name, tags: \.tags, description: \.information, isSelected: false, isTrailing: true, thumbnail: {
            ThumbnailRowPhotoView(cacheController: root.cacheController, model: model, isTrailing: true)
        }, tagAdds: {
            CategoryItemRow(category: model.category)
        })
        .animation(.smooth, value: listModel.displayMode)
#if !os(tvOS)
        .draggable(LinkData(itemId: model.id, module: PhotoDataModel.typeId, name: model.name))
#endif
    }

    var width: CGFloat {
        switch listModel.displayMode {
            case .compact: 160
            case .medium: 128
            case .regular: 96
            @unknown default: 96
        }
    }
}

#Preview(traits: .mockData) {
    @Previewable @Query var models: [PhotoDataModel]
    @Previewable @Environment(\.modelContext) var modelContext
    
    MainRowView(model: models[0])
        .environment(PhotoRootModel(modelContext: modelContext))
        .environment(CacheItemListModel())
        .environment(SearchModel.preview)
        .environment(DeviceRotationModel())
}

