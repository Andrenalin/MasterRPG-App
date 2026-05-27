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
    var searchControllable: any SearchControllable { get }

    func copy(parentModel: (any ItemDataAccessable)?) -> Self
    func copy(listModel: FolderListModel) -> Self
    func detailDestination(for itemId: UUID) -> any NavigationDestination
    func viewerDestination(for itemId: UUID) -> any NavigationDestination
}

extension FolderListControllable {
    public var searchControllable: any SearchControllable {
        DefaultFolderSearchController(itemControllable: itemControllable)
    }

    public func copyModel(parentModel: (any ItemDataAccessable)?) -> FolderListModel {
        FolderListModel(parentModel: parentModel, navigationModel: listModel.navigationModel)
    }

    public func resetItemOnce() {
        guard listModel.updatedOnce == false else { return }
        listModel.updatedOnce = true
        originalItems()
        resetFilter()
    }

    /// Resets the parent model and triggers filtering updates.
    /// When a parent model is set, the list mode is controlled by LinkItemListView.configureParentFiltering()
    /// based on the parent's category (folder → .folder mode, others → .list mode).
    /// UI controls for list mode should be disabled when parentModel is set.
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
        } else if let newSelected = listModel.item(itemId: previousSelectedId ?? listModel.navigationModel.selectedItemId) {
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
        // Cancel any in-flight async search
        listModel.searchTask?.cancel()
        listModel.searchTask = nil

        let searchText = searchModel.searchText

        if !searchText.isEmpty {
            // Async path: delegate to searchControllable for full entry-level search
            let controller = searchControllable
            let expandsEntries = listModel.searchExpandsEntries
            listModel.searchTask = Task { @MainActor in
                let results = await controller.searchItems(searchText: searchText)
                guard !Task.isCancelled else { return }
                let items = buildSearchDisplayItems(from: results, expandsEntries: expandsEntries)
                listModel.displayedItems <=> items
                listModel.displayedParentItems <=> []
                // Re-anchor the selection to the item's new search-mode ID
                if let selectedItemId = listModel.selectedItemId,
                   let matchedItem = items.first(where: { $0.model.id == selectedItemId && $0.entryId == nil }) {
                    listModel.selected <=> matchedItem.id
                    listModel.listSelection <=> Set(arrayLiteral: matchedItem.id)
                }
            }
            return
        }

        // Synchronous tree-filter path (no search text)
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

    // MARK: - Search display item builders

    /// Dispatches to the mode-appropriate builder.
    private func buildSearchDisplayItems(from results: [SearchResult], expandsEntries: Bool) -> [ListItemModel] {
        let selectedItemId = listModel.selectedItemId
        if listDisplayModel.listMode == .list {
            return buildListModeSearch(from: results, expandsEntries: expandsEntries, selectedItemId: selectedItemId)
        } else {
            return buildFolderModeSearch(from: results, expandsEntries: expandsEntries, selectedItemId: selectedItemId)
        }
    }

    /// List mode: flat results sorted by relevance, folders excluded, selected item first.
    private func buildListModeSearch(from results: [SearchResult], expandsEntries: Bool, selectedItemId: UUID?) -> [ListItemModel] {
        var itemOrder: [UUID] = []
        var seen: Set<UUID> = []
        var entryResults: [UUID: [SearchResult]] = [:]

        for result in results {
            // Skip folders in list mode
            if let model = itemControllable.itemSync(for: result.itemId), model.specialCategory { continue }
            if !seen.contains(result.itemId) {
                seen.insert(result.itemId)
                itemOrder.append(result.itemId)
            }
            if result.entryId != nil {
                entryResults[result.itemId, default: []].append(result)
            }
        }

        // Ensure selected item is visible and first
        if let id = selectedItemId {
            if seen.contains(id) {
                if itemOrder.first != id {
                    itemOrder.removeAll { $0 == id }
                    itemOrder.insert(id, at: 0)
                }
            } else if let model = itemControllable.itemSync(for: id), !model.specialCategory {
                itemOrder.insert(id, at: 0)
            }
        }

        return makeSearchItems(from: itemOrder, entryResults: entryResults, expandsEntries: expandsEntries, baseLevel: 0)
    }

    /// Folder mode: preserves tree structure, shows ancestor folders for matches, max 10 levels deep.
    private func buildFolderModeSearch(from results: [SearchResult], expandsEntries: Bool, selectedItemId: UUID?) -> [ListItemModel] {
        let matchingItemIds = Set(results.map(\.itemId))
        var entryResults: [UUID: [SearchResult]] = [:]
        for result in results where result.entryId != nil {
            entryResults[result.itemId, default: []].append(result)
        }

        var output: [ListItemModel] = []

        for (index, originalItem) in listModel.originalItems.enumerated() {
            addFolderSearchItem(
                item: originalItem,
                childIndex: index,
                level: 0,
                matchingItemIds: matchingItemIds,
                entryResults: entryResults,
                expandsEntries: expandsEntries,
                output: &output,
                maxLevel: 10
            )
        }

        // Ensure selected item is visible and first
        if let id = selectedItemId {
            prependSelectedItem(id, entryResults: entryResults, expandsEntries: expandsEntries, output: &output)
        }

        return output
    }

    /// Recursively visits a tree node, appending it (and its matching children) to `output`.
    private func addFolderSearchItem(
        item: ListItemModel,
        childIndex: Int,
        level: Int,
        matchingItemIds: Set<UUID>,
        entryResults: [UUID: [SearchResult]],
        expandsEntries: Bool,
        output: inout [ListItemModel],
        maxLevel: Int
    ) {
        guard level < maxLevel, item.model.displayState == 0 else { return }

        if item.model.specialCategory {
            // Folder / collection: show only when it or a descendant matches
            let childModels = item.model.entries.compactMap { itemControllable.itemSync(for: $0.childId) }
            let isMatch = matchingItemIds.contains(item.model.id)
            guard isMatch || hasDeepMatch(children: childModels, matchingItemIds: matchingItemIds, depth: level + 1, maxLevel: maxLevel) else { return }

            output.append(ListItemModel(
                id: "search-\(level)-\(output.count)-\(item.model.id)",
                model: item.model,
                isOpen: true,
                entryId: nil,
                level: level
            ))

            for (ci, childModel) in childModels.enumerated() {
                guard childModel.displayState == 0 else { continue }
                let childItem = ListItemModel(id: "tmp-\(ci)", model: childModel, entryId: nil, level: level + 1)
                addFolderSearchItem(
                    item: childItem,
                    childIndex: ci,
                    level: level + 1,
                    matchingItemIds: matchingItemIds,
                    entryResults: entryResults,
                    expandsEntries: expandsEntries,
                    output: &output,
                    maxLevel: maxLevel
                )
            }

        } else if matchingItemIds.contains(item.model.id) {
            // Regular item: only show when it matches
            let entries = expandsEntries ? (entryResults[item.model.id] ?? []) : []
            output.append(ListItemModel(
                id: "search-\(level)-\(output.count)-\(item.model.id)",
                model: item.model,
                isOpen: !entries.isEmpty,
                entryId: nil,
                level: level
            ))
            for (ei, er) in entries.enumerated() {
                guard let entryId = er.entryId else { continue }
                output.append(ListItemModel(
                    id: "search-\(level + 1)-\(ei)-\(entryId)",
                    model: item.model,
                    isOpen: false,
                    entryId: entryId,
                    level: level + 1
                ))
            }
        }
    }

    /// Returns true when any descendant of `children` is in `matchingItemIds`, up to `maxLevel`.
    private func hasDeepMatch(children: [any ItemDataAccessable], matchingItemIds: Set<UUID>, depth: Int, maxLevel: Int) -> Bool {
        guard depth < maxLevel else { return false }
        for child in children {
            if matchingItemIds.contains(child.id) { return true }
            if child.specialCategory {
                let grandchildren = child.entries.compactMap { itemControllable.itemSync(for: $0.childId) }
                if hasDeepMatch(children: grandchildren, matchingItemIds: matchingItemIds, depth: depth + 1, maxLevel: maxLevel) { return true }
            }
        }
        return false
    }

    /// Moves the selected item (plus its entry children) to position 0.
    /// If not in `output`, synthesises a level-0 row for it.
    private func prependSelectedItem(_ selectedItemId: UUID, entryResults: [UUID: [SearchResult]], expandsEntries: Bool, output: inout [ListItemModel]) {
        if output.first?.model.id == selectedItemId { return }

        var extractedRows: [ListItemModel] = []

        if let startIdx = output.firstIndex(where: { $0.model.id == selectedItemId && $0.entryId == nil }) {
            // Pull the item row and any immediately following entry rows out
            var endIdx = startIdx + 1
            while endIdx < output.count, output[endIdx].model.id == selectedItemId, output[endIdx].entryId != nil {
                endIdx += 1
            }
            extractedRows = Array(output[startIdx..<endIdx])
            output.removeSubrange(startIdx..<endIdx)
        } else if let model = itemControllable.itemSync(for: selectedItemId) {
            // Selected item not in results — synthesise at level 0
            let entries = expandsEntries ? (entryResults[selectedItemId] ?? []) : []
            extractedRows.append(ListItemModel(
                id: "search-selected-\(model.id)",
                model: model,
                isOpen: !entries.isEmpty,
                entryId: nil,
                level: 0
            ))
            for (ei, er) in entries.enumerated() {
                guard let entryId = er.entryId else { continue }
                extractedRows.append(ListItemModel(
                    id: "search-selected-entry-\(ei)-\(entryId)",
                    model: model,
                    isOpen: false,
                    entryId: entryId,
                    level: 1
                ))
            }
        }

        guard !extractedRows.isEmpty else { return }
        output.insert(contentsOf: extractedRows, at: 0)
    }

    /// Converts a flat ordered ID list into `[ListItemModel]`, appending entry rows when `expandsEntries`.
    private func makeSearchItems(from itemOrder: [UUID], entryResults: [UUID: [SearchResult]], expandsEntries: Bool, baseLevel: Int) -> [ListItemModel] {
        var items: [ListItemModel] = []
        for (index, itemId) in itemOrder.enumerated() {
            guard let model = itemControllable.itemSync(for: itemId) else { continue }
            let entries = expandsEntries ? (entryResults[itemId] ?? []) : []
            items.append(ListItemModel(
                id: "search-\(baseLevel)-\(index)-\(model.id)",
                model: model,
                isOpen: !entries.isEmpty,
                entryId: nil,
                level: baseLevel
            ))
            for (ei, er) in entries.enumerated() {
                guard let entryId = er.entryId else { continue }
                items.append(ListItemModel(
                    id: "search-\(baseLevel + 1)-\(ei)-\(entryId)",
                    model: model,
                    isOpen: false,
                    entryId: entryId,
                    level: baseLevel + 1
                ))
            }
        }
        return items
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

    /// Closes the nearest open parent folder of the currently selected item
    /// and selects that parent folder afterwards.
    func closeParentFolder() {
        guard let itemId = listModel.selectedItemId else { return }
        closeParentFolder(of: itemId)
    }

    /// Opens the selected item if it is a closed folder.
    func openSelectedFolder() {
        guard let itemId = listModel.selectedItemId else { return }
        openFolder(itemId: itemId)
    }

    /// Closes the nearest open parent folder of `itemId` and selects that parent folder.
    func closeParentFolder(of itemId: UUID) {
        guard let index = displayItems.firstIndex(where: { $0.model.id == itemId }) else { return }
        let selectedLevel = displayItems[index].level
        for i in stride(from: index - 1, through: 0, by: -1) {
            let candidate = displayItems[i]
            if candidate.level < selectedLevel && candidate.model.specialCategory && candidate.isOpen {
                toggleFolder(item: candidate)
                listModel.selected = candidate.id
                listModel.listSelection = Set(arrayLiteral: candidate.id)
                listModel.scrollId = candidate.id
                listModel.navigationModel.selectedItemId = candidate.model.id
                return
            }
        }
    }

    /// Opens `itemId` if it is a closed folder.
    func openFolder(itemId: UUID) {
        guard let item = displayItems.first(where: { $0.model.id == itemId }),
              item.model.specialCategory && !item.isOpen else { return }
        toggleFolder(item: item)
    }

    /// Returns true if `itemId` is a closed folder that can be opened.
    func canOpenFolder(itemId: UUID?) -> Bool {
        guard let itemId,
              let item = displayItems.first(where: { $0.model.id == itemId }) else { return false }
        return item.model.specialCategory && !item.isOpen
    }

    /// Returns true if `itemId` has an open parent folder in the visible tree.
    func hasParentFolder(itemId: UUID?) -> Bool {
        guard let itemId,
              let index = displayItems.firstIndex(where: { $0.model.id == itemId }),
              index > 0 else { return false }
        let selectedLevel = displayItems[index].level
        return displayItems[0..<index].contains { $0.level < selectedLevel && $0.model.specialCategory && $0.isOpen }
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
        
        // Always include the currently selected item, even if it doesn't match the search
        if item.model.id == listModel.selectedItemId {
            return item
        }
        
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
