// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI

struct MainRowView: View {
    let model: PhotoDataModel

    @Environment(CacheItemListModel.self) private var cacheModel
    @Environment(PhotoRootModel.self) private var root

    var body: some View {
        ItemRow(itemId: model.id, model: model, cacheItemListModel: cacheModel, isSelected: false, thumbnail: {
            OldThumbnailRowPhotoView(cacheController: root.cacheController, model: model)
        })
#if !os(tvOS)
        .draggable(LinkData(itemId: model.id, module: PhotoDataModel.typeId, name: model.name))
#endif
    }
}

#Preview(traits: .mockData) {
    @Previewable @Query var models: [PhotoDataModel]
    
    MainRowView(model: models.first(where: { $0.id == MockData.previewId })!)
    MainRowView(model: models.first(where: { $0.id == MockData.emptyFolderId })!)
    MainRowView(model: models.first(where: { $0.id == MockData.albumId })!)
    MainRowView(model: PhotoDataModel.dropItem)
}

