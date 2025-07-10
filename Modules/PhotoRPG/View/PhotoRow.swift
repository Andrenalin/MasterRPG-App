// @copyright André Trettin

import CoreRPG
import SwiftUI

struct PhotoRow: View {
    let model: PhotoDataModel

    @Environment(CacheItemListModel.self) private var cacheModel
    @Environment(SearchModel.self) private var searchModel

    var body: some View {
        ItemRow(itemId: model.id, model: model, cacheItemListModel: cacheModel, name: \.name, tags: \.tags, description: \.information, isSelected: false, thumbnail: {
            ThumbnailItem(model: model, highResolution: false)
        }, tagAdds: {
            CategoryItemRow(category: model.category)
        }, actionBar: {
        })
    }
}

