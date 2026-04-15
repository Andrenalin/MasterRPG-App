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
        
    func copy(parentModel: (any ItemDataAccessable)?) -> Self
    func copy(listModel: FolderListModel) -> Self
    func detailDestination(for itemId: UUID) -> any NavigationDestination
    func viewerDestination(for itemId: UUID) -> any NavigationDestination
}

extension FolderListControllable {
    public func copyModel(parentModel: (any ItemDataAccessable)?) -> FolderListModel {
        FolderListModel(parentModel: parentModel, navigationModel: listModel.navigationModel)
    }

    public func resetItemOnce() {
        guard listModel.updatedOnce == false else { return }
        listModel.updatedOnce = true
        originalItems()
        resetFilter()
    }

    public func resetParentModel(model: (any ItemDataAccessable)) {
        if listModel.parentModel?.id != model.id {
            listModel.updatedOnce = true
            listModel.parentModel = model
            originalItems()
            resetFilter()
        }
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
    private func originalItems() {
        let currentItems: [any ItemDataAccessable] = itemControllable.itemDataModel.items.compactMap {
            itemControllable.itemSync(for: $0)
        }
        
        if currentItems.map(\.id) != listModel.originalItems.map(\.model.id) {
            let updatedItems = currentItems.enumerated().map { (index, model) in
                map(model: model, entryId: nil, index: index, level: 0)
            }
            listModel.originalItems <=> updatedItems
        }

        if let parentModel = listModel.parentModel {
            let parentChildrenItems = itemControllable.children(itemId: parentModel.id)

            if parentChildrenItems.map(\.id) != listModel.parentOriginalItems.map(\.model.id) {
                let updatedItems = parentChildrenItems.enumerated().map { (index, model) in
                    map(model: model, entryId: nil, index: index, level: 0)
                }
                listModel.parentOriginalItems <=> updatedItems
            }
        }
    }

    func update() {
        let previousSelectedId = listModel.selectedItemId
        
        originalItems()
        resetFilter()
        
        if let addedItem = listModel.item(itemId: listModel.addedModelId) {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(50))
                listModel.listSelection = Set(arrayLiteral: addedItem.id)
            }
            listModel.addedModelId = nil
        } else if let newSelected = listModel.item(itemId: previousSelectedId) {
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
            return ItemRowModel(itemId: model.id, typeId: itemControllable.config.module)
        }
        listModel.deleteItems(offsets: offsets)
        return removed
    }
    
    func resetFilter() {
        let newlyfilteredOnes: [ListItemModel] = listModel.originalItems.enumerated().flatMap { (index, item) in
            filterSub(item: item, index: index, level: 0, isParent: false)
        }
        if listModel.displayedItems != newlyfilteredOnes {
            listModel.displayedItems <=> newlyfilteredOnes
        }
        
        let newlyParentFilteredOnes: [ListItemModel] = listModel.parentOriginalItems.enumerated().flatMap { (index, item) in
            filterSub(item: item, index: index, level: 0, isParent: true)
        }
        if listModel.displayedParentItems != newlyParentFilteredOnes {
            listModel.displayedParentItems <=> newlyParentFilteredOnes
        }
    }
    
    func filterSub(item: ListItemModel, index: Int, level: Int, isParent: Bool) -> [ListItemModel] {
        guard let itemModel = filter(item: item, level: item.level, isParent: isParent) else { return [] }
        if itemModel.isOpen {
            let newItems = mapSub(model: itemModel.model, entryId: item.entryId, index: index, level: itemModel.level)
            return [itemModel] + newItems.enumerated().flatMap { (index, item) in
                filterSub(item: item, index: index, level: item.level, isParent: isParent)
            }
        }
        return [itemModel]
    }
    
    func toggleFolder(item: ListItemModel) {
        listModel.toggleFolder(itemId: item.model.id, entryId: item.entryId)
        item.isOpen.toggle()
        resetFilter()
    }
    
    func toggleParentFolder(item: ListItemModel) {
        listModel.toggleFolder(itemId: item.model.id, entryId: nil)
        guard let parentItem = listModel.displayedItems.first(where: { $0.model.id == item.model.id && $0.entryId == nil && $0.level == item.level - 1 }) else { return }
        parentItem.isOpen.toggle()
        resetFilter()
    }
}

private extension FolderListControllable {
    func filter(item: ListItemModel, level: Int, isParent: Bool) -> ListItemModel? {
        guard item.model.displayState != 2 else { return nil }
        if isParent == false {
            guard item.model.displayState == 0 else { return nil }
            if listDisplayModel.listMode == .list {
                if item.model.specialCategory {
                    return nil
                }
                if item.entryId == nil && item.level > 0 {
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
    
    func map(model: any ItemDataAccessable, entryId: UUID?, index: Int, level: Int) -> ListItemModel {
        let folderOpened = model.specialCategory ? listModel.isFolderOpen(itemId: model.id, entryId: entryId) : false
        return ListItemModel(id: "\(level)-\(index)-\(model.id)", model: model, isOpen: folderOpened, entryId: entryId, level: level)
    }
    
    func mapSub(model: any ItemDataAccessable, entryId: UUID?, index: Int, level: Int) -> [ListItemModel] {
        if let entryId {
            if let model = itemControllable.subChildren(itemId: model.id, entryId: entryId).first {
                return mapSub(model: model, entryId: nil, index: 0, level: level + 1)
            }
            return []
        }
        guard model.specialCategory else {
            return model.entries.enumerated().map { (subIndex, subModel) in
                let folderOpened = listModel.isFolderOpen(itemId: model.id, entryId: subModel.id)
                return ListItemModel(id: "\(level)-\(subIndex)-\(subModel.id)", model: model, isOpen: folderOpened, entryId: subModel.id, level: level + 1)
            }
        }
        let subModels = model.entries.compactMap { itemControllable.itemSync(for: $0.childId ) }
        return subModels.enumerated().map { (subIndex, subModel) in
            map(model: subModel, entryId: entryId, index: subIndex, level: level + 1)
        }
    }
}
