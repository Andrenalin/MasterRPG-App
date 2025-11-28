// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct TableRow: View {
    let item: ItemRowTreeModel
    let isSelected: Bool
    let cacheItemListModel: CacheItemListModel
    
    @Environment(TableRootModel.self) private var root
    @Environment(ListModel.self) private var itemListModel

    var body: some View {
        @Bindable var model = root.itemController.itemOrEmpty(for: item.model.itemId)
        TableRowModel(item: item, model: model, isSelected: isSelected, cacheItemListModel: cacheItemListModel)
            .onChange(of: model.entries, initial: false) { oldValue, newValue in
                guard item.model.entryId == nil else { return }
                if (oldValue.count != newValue.count) || (oldValue.map { $0.id } != newValue.map { $0.id }) {
                    withAnimation { root.listController(model: itemListModel).update(item: item) }
                }
            }
    }
}

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
