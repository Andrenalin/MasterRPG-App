// @copyright André Trettin

import Foundation
import SwiftUI

@MainActor
public protocol FolderListControllable: Sendable {
    var itemControllable: any ItemControllable { get }

    var listModel: FolderListModel { get }
    var listDisplayModel: ListDisplayModel { get }
    var searchModel: SearchModel { get }
    var cacheListItemModel: CacheItemListModel { get }
    var detailInspectorModel: DetailInspectorModel { get }
    
    func copy(parentModel: (any ItemDataAccessable)?) -> Self
    func detailDestination(for itemId: UUID) -> any NavigationDestination
}

extension FolderListControllable {
    func resetParentModel(model: (any ItemDataAccessable)?) {
        listModel.parentModel = model
        listModel.originalItems = originalItems()
        resetFilter()
    }
    
    var displayItems: [ListItemModel] {
        listModel.displayedItems
    }

    public func selectedModel(for selectedId: UUID?) -> (any ItemDataAccessable)? {
        guard let selectedId else {
            return listModel.selectedModel
        }
        return itemControllable.itemSync(for: selectedId)
    }
}

public extension FolderListControllable {
    private func originalItems() -> [ListItemModel] {
        var currentItems: [any ItemDataAccessable] = []
        if let parentModel = listModel.parentModel {
            currentItems = parentModel.entries.compactMap {
                itemControllable.itemSync(for: $0.childId)
            }
        } else {
            currentItems = itemControllable.itemDataModel.items.compactMap {
                itemControllable.itemSync(for: $0)
            }
        }
        guard currentItems.map(\.id) != listModel.originalItems.map(\.model.id) else {
            return listModel.originalItems
        }
            
        let updatedItems = currentItems.enumerated().map { (index, model) in
            map(model: model, index: index, level: 0)
        }
        listModel.originalItems = updatedItems
        return updatedItems
    }

    func update() {
        let previousSelectedId = listModel.selectedItemId
        
        listModel.originalItems = self.originalItems()
        resetFilter()
        
        if let addedItem = listModel.item(modelId: listModel.addedModelId) {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(50))
                listModel.listSelection = Set(arrayLiteral: addedItem.id)
            }
            listModel.addedModelId = nil
        } else if let newSelected = listModel.item(modelId: previousSelectedId) {
            listModel.listSelection = Set(arrayLiteral: newSelected.id)
            listModel.selected = newSelected.id
            
            listModel.scrollId = newSelected.id
        }
    }
}

extension FolderListControllable {
    func add(model: any ItemDataAccessable) {
        listModel.addedModelId = model.id
    }
    
    @MainActor func delete(offsets: IndexSet) -> [ItemRowModel] {
        let removed = offsets.map {
            let model = displayItems[$0].model
            return ItemRowModel(itemId: model.id, typeId: NetworkModules.none)
        }
        listModel.deleteItems(offsets: offsets)
        return removed
    }
    
    func resetFilter() {
        let newlyfilteredOnes: [ListItemModel] = originalItems().enumerated().flatMap { (index, item) in
            filterSub(item: item, index: index, level: 0)
        }
        if listModel.displayedItems != newlyfilteredOnes {
            listModel.displayedItems <=> newlyfilteredOnes
        }
    }
    
    func filterSub(item: ListItemModel, index: Int, level: Int) -> [ListItemModel] {
        guard let itemModel = filter(item: item, level: item.level) else { return [] }
        if itemModel.isOpen {
            let newItems = mapSub(model: itemModel.model, index: index, level: itemModel.level)
            return [itemModel] + newItems.enumerated().flatMap { (index, item) in
                filterSub(item: item, index: index, level: item.level)
            }
        }
        return [itemModel]
    }
    
    func toggleFolder(item: ListItemModel) {
        guard item.model.specialCategory else { return }
        
        listModel.toggleFolder(itemId: item.model.id)
        item.isOpen.toggle()
        resetFilter()
    }
}

private extension FolderListControllable {
    func filter(item: ListItemModel, level: Int) -> ListItemModel? {
        guard item.model.displayState != 2 else { return nil }
        if let parentModel = listModel.parentModel {
            if !parentModel.entries.contains(where: { $0.childId == item.model.id }) {
                return nil
            }
        } else {
            guard item.model.displayState == 0 else { return nil }
            if listDisplayModel.listMode == .list {
                if item.model.specialCategory {
                    return nil
                }
                if item.level > 0 {
                    return nil
                }
            } else {
                if let parentId = listModel.parentModel?.id {
                    if item.model.parentId != parentId {
                        return nil
                    }
                } else if item.level == 0 {
                    if item.model.parentId != nil {
                        return nil
                    }
                }
            }
        }
        if !searchModel.selectedTokens.isEmpty {
            let selectedTags = searchModel.selectedTokens.map { $0.tag }
            if !item.model.tags.contains(selectedTags) {
                return nil
            }
        }
        guard !searchModel.searchText.isEmpty else { return item }
        return item.model.name.localizedStandardContains(searchModel.searchText) ||
        item.model.description.localizedStandardContains(searchModel.searchText) ? item : nil
    }
    
    func map(model: any ItemDataAccessable, index: Int, level: Int) -> ListItemModel {
        let folderOpened = model.specialCategory ? listModel.isFolderOpen(itemId: model.id) : false
        return ListItemModel(id: "\(level)-\(index)-\(model.id)", model: model, isOpen: folderOpened, level: level)
    }
    
    func mapSub(model: any ItemDataAccessable, index: Int, level: Int) -> [ListItemModel] {
        let subModels = model.entries.compactMap { itemControllable.itemSync(for: $0.childId ) }
        return subModels.enumerated().map { (subIndex, subModel) in
            map(model: subModel, index: subIndex, level: level + 1)
        }
    }
}
