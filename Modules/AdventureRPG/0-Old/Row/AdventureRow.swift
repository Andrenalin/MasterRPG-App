// @copyright André Trettin

import CoreRPG
import SwiftUI
import AudioRPG
import MapRPG
import PhotoRPG
import TableRPG
import SpaceRPG
import PdfRPG
import WeatherRPG
import CharacterRPG

struct AdventureRow: View {
    let item: ItemRowTreeModel
    let isSelected: Bool
    let cacheItemListModel: CacheItemListModel

    @Environment(AdventureRootModel.self) private var root
    @Environment(ListModel.self) private var itemListModel

    var body: some View {
        switch item.model.typeId {
        case .audio:
            root.audioRoot.viewController.rowView(root: root.audioRoot, item: item, isSelected: isSelected, cacheItemListModel: cacheItemListModel)
        case .map:
            root.mapRoot.viewController.rowView(root: root.mapRoot, item: item, isSelected: isSelected, cacheItemListModel: cacheItemListModel)
        case .pdf:
            root.pdfRoot.viewController.rowView(root: root.pdfRoot, item: item, isSelected: isSelected, cacheItemListModel: cacheItemListModel)
        case .photo:
            root.photoRoot.viewController.rowView(root: root.photoRoot, item: item, isSelected: isSelected, cacheItemListModel: cacheItemListModel)
        case .space:
            root.spaceRoot.viewController.rowView(root: root.spaceRoot, item: item, isSelected: isSelected, cacheItemListModel: cacheItemListModel)
        case .table:
            root.tableRoot.viewController.rowView(root: root.tableRoot, item: item, isSelected: isSelected, cacheItemListModel: cacheItemListModel)
        case .value, .editor:
            root.valueRoot.viewController.rowView(root: root.valueRoot, item: item, isSelected: isSelected, cacheItemListModel: cacheItemListModel)
        case .weather:
            root.weatherRoot.viewController.rowView(root: root.weatherRoot, item: item, isSelected: isSelected, cacheItemListModel: cacheItemListModel)
        case .adventure:
            rowAdventureView
        default:
            Text("Module \(item.model.typeId.token) not supported", bundle: .module)
        }
    }
    
    private var rowAdventureView: some View {
        Group {
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
}
