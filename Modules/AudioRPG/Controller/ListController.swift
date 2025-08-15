//// @copyright André Trettin
//
//import CoreRPG
//import SwiftData
//import SwiftUI
//
//struct ListController {
//    
//    @MainActor
//    func update(items: [AudioDataModel], listModel: ListModel, listDisplayModel: ListDisplayModel, searchModel: SearchModel, parentModel: AudioDataModel?) {
//     
//        totalItems(items: items, listModel: listModel, listDisplayModel: listDisplayModel, searchModel: searchModel, parentModel: parentModel)
//    }
//    
//    @MainActor
//    private func filteredItems(items: [AudioDataModel], listModel: ListModel, listDisplayModel: ListDisplayModel, searchModel: SearchModel, parentModel: AudioDataModel?, withParentFilter: Bool = true) -> [AudioDataModel] {
//        var filtered = items
//        if withParentFilter {
//            if parentModel == nil && listDisplayModel.listMode == .list {
//                filtered = filtered.filter { $0.category != .folder && $0.category != EditController.Model.collectionCategory }
//            } else {
//                filtered = filtered.filter { $0.parentId == listModel.selectedParentId }
//            }
//        }
//        if !searchModel.selectedTokens.isEmpty {
//            let selectedTags = searchModel.selectedTokens.map { $0.tag }
//            filtered = filtered.filter { $0.tags.contains(selectedTags) }
//        }
//        guard !searchModel.searchText.isEmpty else { return filtered }
//        return filtered.filter {
//            $0.name.localizedStandardContains(searchModel.searchText) ||
//            $0.information.localizedStandardContains(searchModel.searchText)
//        }
//    }
//    
//    @MainActor
//    private func totalItems(items: [AudioDataModel], listModel: ListModel, listDisplayModel: ListDisplayModel, searchModel: SearchModel, parentModel: AudioDataModel?, level: Int = 0, withParentFilter: Bool = true, entryIds: [UUID: UUID] = [:]) -> [ItemListModel] {
//        var total: [ItemListModel] = []
//        guard level < 10 else { return total }
//        
//        let filtered = filteredItems(items: items, listModel: listModel, listDisplayModel: listDisplayModel, searchModel: searchModel, parentModel: parentModel, withParentFilter: withParentFilter)
//        
//        let sorted: [AudioDataModel]
//        if parentModel?.category == .folder {
//            sorted = filtered.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
//        } else {
//            sorted = filtered
//        }
//        sorted.forEach { item in
//            let id = item.category == AudioDataModel.collectionCategory ? entryIds[item.id, default: item.id] : item.id
//            let model = listModel.subItemModel(for: id, itemId: item.id, level: level)
//            total.append(model)
//            if item.specialCategory && listModel.isFolderOpen(itemId: item.id) {
//                let (newItems, newEntryIds) = item.subItems
//                total.append(contentsOf: totalItems(items: newItems, listModel: listModel, listDisplayModel: listDisplayModel, searchModel: searchModel, parentModel: parentModel, level: level + 1, withParentFilter: false, entryIds: newEntryIds))
//            }
//        }
//        if total.isEmpty && parentModel != nil {
//            total.append(ItemListModel(id: AudioDataModel.dropItem.id, itemId: AudioDataModel.dropItem.id, isOpen: false, level: level))
//        }
//        return total
//    }
//
//}
