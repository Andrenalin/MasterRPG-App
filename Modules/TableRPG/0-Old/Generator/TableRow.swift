// @copyright André Trettin

import CoreRPG
import SwiftUI

struct TableRowModel: View {
    let item: ItemRowTreeModel
    let model: TableModel
    let isSelected: Bool
    let cacheItemListModel: CacheItemListModel

    var body: some View {
        if item.model.entryId == nil {
            MainRow(model: model, isSelected: isSelected, cacheItemListModel: cacheItemListModel)
        } else {
            EntryRow(model: model, item: item, isEditing: false, cacheItemListModel: cacheItemListModel)
        }
    }
}
