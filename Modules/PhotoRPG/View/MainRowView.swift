// @copyright André Trettin

import CoreRPG
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
//        .applyIf(valueFor(iOS: true, macOS: !childrenConfiguration.canNavigate, tvOS: false, visionOS: true)) { content in
//            content.draggable(LinkData(item: item, name: listController.itemControllable.createLink(model: item.model)))
//        }

    }
}

