// @copyright André Trettin

import Foundation
import SwiftData
import SwiftUI

@MainActor
public protocol OldListControllable: Sendable {
    associatedtype Model: ItemDataAccessable, ItemDataModelable, ListItemFolderable, PersistentModel

    var modelContext: ModelContext { get }
    
    var listModel: OldListModel { get }
    var listDisplayModel: ListDisplayModel { get }
    var searchModel: SearchModel { get }
}

extension OldListControllable {
    func displayItems(for parentModel: Model?) -> [OldListItemModel] {
        guard let parentModel else { return listModel.displayedItems }
        return lastListModel(for: parentModel).displayedItems
    }

    func listModel(for parentModel: Model?) -> OldListModel {
        guard let parentModel else { return self.listModel }
        return lastListModel(for: parentModel)
    }

    private func lastListModel(for parentModel: Model) -> OldListModel {
        guard let subListModel = listModel.subListModel, subListModel.selectedParentId == parentModel.id else {
            let listModel = OldListModel(listModel: listModel, parentId: parentModel.id, lastFolderId: parentModel.isFolder ? parentModel.id : listModel.lastFolderId)
            listModel.subListModel = listModel
            update(items: parentModel.subItems.0, on: listModel)
            return listModel
        }
        return subListModel
    }

}

public extension OldListControllable {
    func update(items: [Model]) {
        update(items: items, on: listModel)
    }

    private func update(items: [Model], on listModel: OldListModel) {
        listModel.originalItems = items.enumerated().flatMap { (index, model) in
            map(model: model, index: index, level: 0)
        }
        listModel.displayedItems = listModel.originalItems.compactMap { filter(item: $0) }
    }
}

extension OldListControllable {
    func add(model: Model) {
        let newModel = map(model: model, index: 0, level: 0)
        listModel.displayedItems.insert(contentsOf: newModel, at: 0)
        listModel.selected = newModel.first?.id
    }
    
    func resetFilter() {
        listModel.displayedItems = listModel.originalItems.compactMap { filter(item: $0) }
    }
    
    func toggleFolder(item: OldListItemModel) {
        guard item.isSpecial else { return }
        guard let index = listModel.originalItems.firstIndex(where: { item.id == $0.id }) else { return }
        if item.isOpen {
            // fold
            let nextIndex = listModel.originalItems.index(after: index)
            if nextIndex < listModel.originalItems.endIndex {
                let endIndex = listModel.originalItems[nextIndex...].firstIndex(where: { $0.level == item.level }) ?? listModel.originalItems.endIndex
                listModel.originalItems.remove(atOffsets: IndexSet(nextIndex..<endIndex))
            }
            listModel.toggleFolder(itemId: item.itemId)
        } else {
            // expand
            listModel.toggleFolder(itemId: item.itemId)
            if let model = Model.model(modelContext: modelContext, id:listModel.originalItems[index].itemId) {
                let newItems = map(model: model, index: index, level: item.level).dropFirst()
                let nextIndex = listModel.originalItems.index(after: index)
                listModel.originalItems.insert(contentsOf: newItems, at: nextIndex)
            }
        }
        item.isOpen.toggle()
        listModel.displayedItems = listModel.originalItems.compactMap { filter(item: $0) }
    }
}

private extension OldListControllable {
    func filter(item: OldListItemModel) -> OldListItemModel? {
        if listDisplayModel.listMode == .list {
            if item.isSpecial {
                return nil
            }
        } else {
            if item.level == 0 {
                if item.parentId != nil {
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
    
    func map(model: Model, index: Int, level: Int) -> [OldListItemModel] {
        let folderOpened = model.specialCategory ? listModel.isFolderOpen(itemId: model.id) : false
        let itemModel = OldListItemModel(id: "\(level)-\(index)-\(model.id)", itemId: model.id, isOpen: folderOpened, level: level, isSpecial: model.specialCategory, name: model.name, information: model.information, tags: model.tags, parentId: model.parentId)
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
