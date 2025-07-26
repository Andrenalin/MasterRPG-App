// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI

struct MainRowView: View {
    let model: SpaceDataModel

    @Environment(CacheItemListModel.self) private var cacheModel
    @Environment(SearchModel.self) private var searchModel
    @Environment(SpaceRootModel.self) private var root

    var body: some View {
        ItemRow(itemId: model.id, model: model, cacheItemListModel: cacheModel, name: \.name, tags: \.tags, description: \.information, isSelected: false, thumbnail: {
            ThumbnailRowPhotoView(cacheController: root.cacheController, model: model)
        }, tagAdds: {
            CategoryItemRow(category: model.category)
        })
#if !os(tvOS)
        .draggable(LinkData(itemId: model.id, module: SpaceDataModel.typeId, name: model.name))
#endif
    }
}

#Preview(traits: .mockData) {
    @Previewable @Query var models: [SpaceDataModel]
    @Previewable @Environment(\.modelContext) var modelContext
    
    MainRowView(model: models[0])
        .environment(SpaceRootModel(modelContext: modelContext))
        .environment(CacheItemListModel())
        .environment(SearchModel.preview(modelContext: modelContext, module: SpaceDataModel.typeId))
        .environment(DeviceRotationModel())
}

