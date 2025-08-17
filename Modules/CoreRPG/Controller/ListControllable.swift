// @copyright André Trettin

import Foundation
import SwiftData
import SwiftUI

public protocol ListControllable: Sendable {
    associatedtype Model: ItemDataAccessable, ItemDataModelable, ListItemFolderable, PersistentModel

    var listModel: ListModel { get }
    var listDisplayModel: ListDisplayModel { get }
    var searchModel: SearchModel { get }
}

public extension ListControllable {
    @MainActor func resetFilter() {
        listModel.displayedItems = listModel.originalItems.compactMap { filter(item: $0) }
    }
    
    @MainActor func filter(item: ListItemModel) -> ListItemModel? {
        if listDisplayModel.listMode == .list {
            if item.isSpecial {
                return nil
            }
        } else {
            if item.level == 0 {
                if item.parentId != listModel.selectedParentId {
                    return nil
                }
            }
        }
        if !searchModel.selectedTokens.isEmpty {
            let selectedTags = searchModel.selectedTokens.map { $0.tag }
            if !item.tags.contains(selectedTags) {
                return nil
            }
        }
        guard !searchModel.searchText.isEmpty else { return item }
        return item.name.localizedStandardContains(searchModel.searchText) ||
        item.information.localizedStandardContains(searchModel.searchText) ? item : nil
    }
    
    @MainActor func update(items: [Model]) {
        listModel.originalItems = items.enumerated().flatMap { (index, item) in
            map(item: item, index: index, level: 0)
        }
        listModel.displayedItems = listModel.originalItems.compactMap { filter(item: $0) }
    }
    
    @MainActor private func map(item: Model, index: Int, level: Int) -> [ListItemModel] {
        let folderOpened = item.specialCategory ? listModel.isFolderOpen(itemId: item.id) : false
        let itemModel = ListItemModel(id: "\(level)-\(index)-\(item.id)", itemId: item.id, isOpen: folderOpened, level: level, isSpecial: item.specialCategory, name: item.name, information: item.information, tags: item.tags)
        var models = [itemModel]
        if folderOpened {
            let subItems = item.subItems.0
            let subItemModels = subItems.enumerated().flatMap { (subIndex, subItem) in
                map(item: subItem, index: subIndex, level: level + 1)
            }
            models.append(contentsOf: subItemModels)
        }
        return models
    }
}
