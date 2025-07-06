// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct PhotoRow: View {
    let model: PhotoDataModel
    @Environment(ListModel.self) private var listModel
    @Environment(CacheItemListModel.self) private var cacheModel
    
    var body: some View {
        ItemRow(itemId: model.id, model: model, cacheItemListModel: cacheModel, name: \.name, tags: \.tags, description: \.information, isSelected: false, thumbnail: {
            //ThumbnailItem(root: root, model: model, highResolution: false)
            Text(listModel.searchText)
        }, tagAdds: {
            CategoryItemRow(category: model.category)
        }, actionBar: {
        })
    }
}

