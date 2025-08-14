// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI

struct MainRowView: View {
    let model: SpaceDataModel

    @Environment(CacheItemListModel.self) private var cacheModel
    @Environment(SpaceRootModel.self) private var root

    var body: some View {
        ItemRow(itemId: model.id, model: model, cacheItemListModel: cacheModel, thumbnail: {
            ThumbnailRowPhotoView(cacheController: root.cacheController, model: model)
        })
#if !os(tvOS)
        .draggable(LinkData(itemId: model.id, module: SpaceDataModel.typeId, name: model.name))
#endif
    }
}

#Preview(traits: .mockData) {
    @Previewable @Query var models: [SpaceDataModel]
    
    MainRowView(model: models[0])
}

