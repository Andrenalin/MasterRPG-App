// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct WeatherRow: View {
    let item: ItemRowTreeModel
    let isSelected: Bool
    let cacheItemListModel: CacheItemListModel

    @Environment(WeatherRoot.self) private var root
    @Environment(ListModel.self) private var itemListModel
    
    var body: some View {
        if item.model.entryId == nil {
            MainRow(model: root.itemController.itemOrEmpty(for: item.model.itemId), isSelected: isSelected, cacheItemListModel: itemListModel.cacheItemList.itemCache(for: item.id))
        } else {
            EntryRow(item: item, isSelected: isSelected)
        }
    }
}
