// @copyright André Trettin

import Foundation
import SwiftData
import SwiftUI

@MainActor
public protocol ListControllable: Sendable {
    var listModel: ListModel { get }
    var listDisplayModel: ListDisplayModel { get }
    var searchModel: SearchModel { get }
}

extension ListControllable {
    func displayItems(for parentModel: ItemDataModel?) -> [ListItemModel] {
        guard let parentModel else { return listModel.displayedItems }
        return lastListModel(for: parentModel).displayedItems
    }

    func listModel(for parentModel: ItemDataModel?) -> ListModel {
        guard let parentModel else { return self.listModel }
        return lastListModel(for: parentModel)
    }

    private func lastListModel(for parentModel: ItemDataModel) -> ListModel {
        guard let subListModel = listModel.subListModel, subListModel.selectedParentId == parentModel.id else {
            let listModel = ListModel(listModel: listModel, parentId: parentModel.id, lastFolderId: parentModel.isFolder ? parentModel.id : listModel.lastFolderId)
            listModel.subListModel = listModel
            update(items: parentModel.subItems.0, on: listModel)
            return listModel
        }
        return subListModel
    }
}

public extension ListControllable {
    func update(items: [ItemDataModel]) {
        update(items: items, on: listModel)
    }

    private func update(items: [ItemDataModel], on listModel: ListModel) {
        let previousSelectedId = listModel.selectedItemId
        
        guard listModel.originalItems.map({ $0.model.id }) != items.map(\.id) else { return }
        listModel.originalItems = items.enumerated().flatMap { (index, model) in
            map(model: model, index: index, level: 0)
        }
        listModel.displayedItems = listModel.originalItems.compactMap { filter(item: $0) }
        
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

extension ListControllable {
    func add(model: ItemDataModel) {
        listModel.addedModelId = model.id
    }
    
    func resetFilter() {
        listModel.displayedItems = listModel.originalItems.compactMap { filter(item: $0) }
    }
    
    func toggleFolder(item: ListItemModel) {
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
        listModel.displayedItems = listModel.originalItems.compactMap { filter(item: $0) }
    }
}

private extension ListControllable {
    func filter(item: ListItemModel) -> ListItemModel? {
        if listDisplayModel.listMode == .list {
            if item.model.specialCategory {
                return nil
            }
        } else {
            if item.level == 0 {
                if item.model.parentId != nil {
                    return nil
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
        item.model.information.localizedStandardContains(searchModel.searchText) ? item : nil
    }
    
    func map(model: ItemDataModel, index: Int, level: Int) -> [ListItemModel] {
        let folderOpened = model.specialCategory ? listModel.isFolderOpen(itemId: model.id) : false
        let itemModel = ListItemModel(id: "\(level)-\(index)-\(model.id)", model: model, isOpen: folderOpened, level: level)
        var models = [itemModel]
        if folderOpened {
            let subModels = model.subItems.0
            let subItemModels = subModels.enumerated().flatMap { (subIndex, subModel) in
                map(model: subModel, index: subIndex, level: level + 1)
            }
            models.append(contentsOf: subItemModels)
        }
        return models
    }
}
