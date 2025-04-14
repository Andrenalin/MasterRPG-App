// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct DiceRow: View {
    let item: ItemRowTreeModel
    let isSelected: Bool
    let cacheItemListModel: CacheItemListModel

    @Environment(DiceRoot.self) private var root
    @Environment(ListModel.self) private var itemListModel
    
    var body: some View {
        if item.model.entryId != nil {
            EntryRow(root: root, item: item)
        } else {
            MainRow(model: root.itemController.itemOrEmpty(for: item.model.itemId), isSelected: isSelected, cacheItemListModel: itemListModel.cacheItemList.itemCache(for: item.id))
        }
    }
}
