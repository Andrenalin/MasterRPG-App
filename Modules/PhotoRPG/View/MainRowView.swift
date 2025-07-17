// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI

struct MainRowView: View {
    let model: PhotoDataModel

    @Environment(CacheItemListModel.self) private var cacheModel
    @Environment(SearchModel.self) private var searchModel

    var body: some View {
        ItemRow(itemId: model.id, model: model, cacheItemListModel: cacheModel, name: \.name, tags: \.tags, description: \.information, isSelected: false, thumbnail: {
            PlainPhotoView(model: model, size: .maxHeightWidth(96), ratio: .fill, hasRoundedCorners: true, highResolution: false)
        }, tagAdds: {
            CategoryItemRow(category: model.category)
        }, actionBar: {
        })
        .draggable(LinkData(itemId: model.id, module: .photo, name: model.name))
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

