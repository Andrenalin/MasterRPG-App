// @copyright André Trettin

import AndrenalinKit
import SwiftUI
import AudioRPG
import PdfRPG
import PhotoRPG
import RPGTables
import RPGValues

struct MapRow: View {
    let item: ItemRowTreeModel
    let isSelected: Bool
    let cacheItemListModel: CacheItemListModel
    
    @Environment(MapRootModel.self) private var root
    @Environment(ListModel.self) private var itemListModel
    
    var body: some View {
        switch item.model.typeId {
        case .audio:
            root.audioRoot.viewController.rowView(root: root.audioRoot, item: item, isSelected: isSelected, cacheItemListModel: cacheItemListModel)
        case .pdf:
            root.pdfRoot.viewController.rowView(root: root.pdfRoot, item: item, isSelected: isSelected, cacheItemListModel: cacheItemListModel)
        case .photo:
            root.photoRoot.viewController.rowView(root: root.photoRoot, item: item, isSelected: isSelected, cacheItemListModel: cacheItemListModel)
        case .table:
            root.tableRoot.viewController.rowView(item: item, isSelected: isSelected, cacheItemListModel: cacheItemListModel)
        case .value, .editor:
            root.valueRoot.viewController.rowView(item: item, isSelected: isSelected, cacheItemListModel: cacheItemListModel)
        case .map:
            rowMapView
        default:
            Text("Module \(item.model.typeId.token) not supported", bundle: .module)
        }
    }
    
    @ViewBuilder
    private var rowMapView: some View {
        @Bindable var model = root.itemController.itemOrEmpty(for: item.model.itemId)
        if item.model.entryId == nil {
            MainRow(model: model, isSelected: isSelected, cacheItemListModel: cacheItemListModel)
                .onChange(of: model.entries, initial: false) { oldValue, newValue in
                    if (oldValue.count != newValue.count) || (oldValue.map { $0.id } != newValue.map { $0.id }) {
                        withAnimation { root.listController(model: itemListModel).update(item: item) }
                    }
                }
        } else {
            EntryRow(model: model, item: item, isEditing: false, cacheItemListModel: cacheItemListModel)
        }
    }
}
