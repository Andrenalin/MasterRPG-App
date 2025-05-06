// @copyright André Trettin

import AndrenalinKit
import SwiftUI
import RPGPdfs
import RPGPhotos
import RPGTables

struct ValueRow: View {
    let item: ItemRowTreeModel
    let isSelected: Bool
    let hasQuickEditor: Bool
    let cacheItemListModel: CacheItemListModel

    @Environment(ValueRoot.self) private var root
    @Environment(ListModel.self) private var itemListModel
    
    var body: some View {
        switch item.model.typeId {
        case .pdf:
            root.pdfRoot.viewController.rowView(item: item, isSelected: isSelected, cacheItemListModel: cacheItemListModel)
        case .photo:
            root.photoRoot.viewController.rowView(item: item, isSelected: isSelected, cacheItemListModel: cacheItemListModel)
        case .table:
            root.tableRoot.viewController.rowView(item: item, isSelected: isSelected, cacheItemListModel: cacheItemListModel)
        case .value:
            rowValueView
        case .editor:
            editValueView
        default:
            Text("Module \(item.model.typeId.token) not supported", bundle: .module)
        }
    }

    @ViewBuilder
    private var rowValueView: some View {
        @Bindable var model = root.itemController.itemOrEmpty(for: item.model.itemId)
        ValueRowModel(item: item, model: model, isSelected: isSelected, hasQuickEditor: hasQuickEditor, cacheItemListModel: cacheItemListModel)
            .onChange(of: model.entries, initial: false) { oldValue, newValue in
                if (oldValue.count != newValue.count) || (oldValue.map { $0.id } != newValue.map { $0.id }) {
                    withAnimation { root.listController(model: itemListModel).update(item: item) }
                }
            }
            .onChange(of: model.quickEditEntries, initial: false) { oldValue, newValue in
                if (oldValue.count != newValue.count) {
                    withAnimation { root.listController(model: itemListModel).update(item: item) }
                }
            }
    }

    @ViewBuilder
    private var editValueView: some View {
        @Bindable var model = root.itemController.itemOrEmpty(for: item.model.itemId)
        if let entryId = item.model.entryId {
            QuickEditValueRow(root: root, editController: root.editController(type: .main), itemId: item.model.itemId, entryId: entryId)
        }
    }
}

struct ValueRowModel: View {
    let item: ItemRowTreeModel
    let model: ValueModel
    let isSelected: Bool
    let hasQuickEditor: Bool
    let cacheItemListModel: CacheItemListModel

    @Environment(ValueRoot.self) private var root
    
    var body: some View {
        if item.model.entryId == nil {
            MainRow(model: model, isSelected: isSelected, cacheItemListModel: cacheItemListModel)
        } else {
            EntryRow(linkController: root.linkController, model: model, item: item, isEditing: false, hasQuickEditor: hasQuickEditor, cacheItemListModel: cacheItemListModel)
        }
    }
}
