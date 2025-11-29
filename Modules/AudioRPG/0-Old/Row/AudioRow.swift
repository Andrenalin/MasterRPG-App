// @copyright André Trettin

import CoreRPG
import SwiftUI

struct AudioRow: View {
    let item: ItemRowTreeModel
    let isSelected: Bool
    let cacheItemListModel: CacheItemListModel
    
    @Environment(AudioRootModel.self) private var root
    @Environment(ListModel.self) private var itemListModel
    
    var body: some View {
        @Bindable var model = root.itemController.itemOrEmpty(for: item.model.itemId)
        if item.model.entryId == nil {
            MainRow(model: model, isSelected: isSelected, cacheItemListModel: cacheItemListModel)
                .onChange(of: model.entries, initial: false) { oldValue, newValue in
                    if (oldValue.count != newValue.count) || (oldValue.map { $0.id } != newValue.map { $0.id }) {
                        withAnimation { root.listController(model: itemListModel).update(item: item) }
                    }
                }
        } else {
            EntryRow(item: item, isSelected: isSelected, cacheItemListModel: cacheItemListModel)
        }
    }
}

#Preview {
    AudioRow(item: ItemRowTreeModel.preview, isSelected: true, cacheItemListModel: .preview)
        .environment(AudioRootModel.preview)
        .environment(ListModel.preview)
}
