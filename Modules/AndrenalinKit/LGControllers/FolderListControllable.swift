// @copyright André Trettin

import CoreExternalRPG
import Foundation
import SwiftUI

@MainActor
public protocol FolderListControllable: Sendable {
    var listModel: FolderListModel { get }
    var listDisplayModel: ListDisplayModel { get }
    var searchModel: SearchModel { get }
    var cacheListItemModel: CacheItemListModel { get }
    
    //func detailDestination(for itemId: UUID) -> any NavigationDestination
}

extension FolderListControllable {
    func displayItems(for parentModel: (any ItemDataAccessable)?) -> [ListItemModel] {
        guard let parentModel else { return listModel.displayedItems }
        return lastListModel(for: parentModel).displayedItems
    }

    func listModel(for parentModel: (any ItemDataAccessable)?) -> FolderListModel {
        guard let parentModel else { return self.listModel }
        return lastListModel(for: parentModel)
    }

    private func lastListModel(for parentModel: any ItemDataAccessable) -> FolderListModel {
        guard let subListModel = listModel.subListModel, subListModel.selectedParentId == parentModel.id else {
            let newListModel = FolderListModel(listModel: listModel, parentId: parentModel.id, lastFolderId: parentModel.isFolder ? parentModel.id : listModel.lastFolderId)
            listModel.subListModel = newListModel
            return newListModel
        }
        return subListModel
    }
    
    public func selectedModel(for selectedId: UUID?) -> (any ItemDataAccessable)? {
        guard let selectedId else {
            let subListmodel = listModel.lastSubListModel()
            return subListmodel.selectedModel
        }
        return nil // ItemDataModel.model(modelContext: modelContext, id: selectedId)
    }
}

public extension FolderListControllable {
//    func detailDestination(for itemId: UUID) -> any NavigationDestination {
//        ItemRootRoute.detail(itemId)
//    }

    func update(items: [any ItemDataAccessable], parentModel: (any ItemDataAccessable)?) {
        if let parentModel {
//            let subItems = items.filter { $0.parentId == parentModel.id }
//            update(items: subItems, on: listModel(for: parentModel), parentModel: parentModel)
        } else {
            update(items: items, on: listModel(for: parentModel), parentModel: parentModel)
        }
    }

    private func update(items: [any ItemDataAccessable], on listModel: FolderListModel, parentModel: (any ItemDataAccessable)?) {
        let previousSelectedId = listModel.selectedItemId
        
        guard listModel.originalItems.map({ $0.model.id }) != items.map(\.id) else {
            resetFilter(on: listModel, parentModel: parentModel)
            return
        }
        listModel.originalItems = items.enumerated().flatMap { (index, model) in
            map(model: model, index: index, level: 0)
        }
        
        resetFilter(on: listModel, parentModel: parentModel)
        
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
    
    @MainActor func delete(offsets: IndexSet, parentModel: (any ItemDataAccessable)?) -> [ItemRowModel] {
        let displayItems = displayItems(for: parentModel)
        let removed = offsets.map {
            let model = displayItems[$0].model
            return ItemRowModel(itemId: model.id, typeId: NetworkModules.none)
        }
        listModel(for: parentModel).deleteItems(offsets: offsets)
        return removed
    }
    
    func resetFilter(parentModel: (any ItemDataAccessable)?) {
        resetFilter(on: listModel(for: parentModel), parentModel: parentModel)
    }
    
    private func resetFilter(on listModel: FolderListModel, parentModel: (any ItemDataAccessable)?) {
        let newlyfilteredOnes = listModel.originalItems.compactMap { filter(item: $0, parentModel: parentModel) }
        if listModel.displayedItems != newlyfilteredOnes {
            listModel.displayedItems <=> newlyfilteredOnes
        }
    }
    
    func toggleFolder(item: ListItemModel, parentModel: (any ItemDataAccessable)?) {
        guard item.model.specialCategory else { return }
        guard let index = listModel.originalItems.firstIndex(where: { item.id == $0.id }) else { return }
        if item.isOpen {
            // fold
            let nextIndex = listModel.originalItems.index(after: index)
            if nextIndex < listModel.originalItems.endIndex {
                let endIndex = listModel.originalItems[nextIndex...].firstIndex(where: { $0.level == item.level }) ?? listModel.originalItems.endIndex
                listModel.originalItems.remove(atOffsets: IndexSet(nextIndex..<endIndex))
            }
            listModel.toggleFolder(itemId: item.model.id)
        } else {
            // expand
            listModel.toggleFolder(itemId: item.model.id)
            let model = item.model //ItemDataModel.model(modelContext: item.model.modelContext, id: listModel.originalItems[index].model.id) {
                let newItems = map(model: model, index: index, level: item.level).dropFirst()
                let nextIndex = listModel.originalItems.index(after: index)
                listModel.originalItems.insert(contentsOf: newItems, at: nextIndex)
        }
        item.isOpen.toggle()
        resetFilter(on: listModel, parentModel: parentModel)
    }
}

private extension FolderListControllable {
    func filter(item: ListItemModel, parentModel: (any ItemDataAccessable)?) -> ListItemModel? {
        if listDisplayModel.listMode == .list {
            if item.model.specialCategory {
                return nil
            }
        } else {
            if let parentId = parentModel?.id {
//                if item.model.parentId != parentId {
//                    return nil
//                }
            } else if item.level == 0 {
//                if item.model.parentId != nil {
//                    return nil
//                }
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
    
    func map(model: any ItemDataAccessable, index: Int, level: Int) -> [ListItemModel] {
        let folderOpened = model.specialCategory ? listModel.isFolderOpen(itemId: model.id) : false
        let itemModel = ListItemModel(id: "\(level)-\(index)-\(model.id)", model: model, isOpen: folderOpened, level: level)
        var models = [itemModel]
        if folderOpened {
//            let subModels = model.subItems.0
//            let subItemModels = subModels.enumerated().flatMap { (subIndex, subModel) in
//                map(model: subModel, index: subIndex, level: level + 1)
//            }
//            models.append(contentsOf: subItemModels)
        }
        return models
    }
}
