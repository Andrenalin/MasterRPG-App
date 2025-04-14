// @copyright André Trettin

import Foundation
import SwiftUI

public protocol ListControllable: Sendable {
    var itemControllable: any ItemControllable { get }
    var model: ListModel { get }
    
    var canGroup: Bool { get }
    func groupItems(for selection: Set<ItemRowTreeModel>) async
}

// MARK: - Group

public extension ListControllable {
    var canGroup: Bool { false }
    func groupItems(for selection: Set<ItemRowTreeModel>) {}
}

// MARK: - Update

public extension ListControllable {
    @MainActor
    func update(models: [ItemRowModel]) {
        var scrollIndexBefore: Int? = nil
        if let selectedItem = model.selectedItem {
            scrollIndexBefore = model.filteredItems.firstIndex(where: { $0.id == selectedItem.id })
        }
        let entries = models // model.filterModel == nil ? models : models.filter { $0 == model.filterModel }
        let updatedItems = updateSubList(entries: entries, items: model.unfilteredItems, idItems: model.idItems, level: 0)
        model.unfilteredItems = updatedItems.0
        model.idItems = updatedItems.1
        resetFilter()
        if let selectedItem = model.selectedItem {
            if let scrollIndexAfter = model.filteredItems.firstIndex(where: { $0.id == selectedItem.id }) {
                if scrollIndexAfter != scrollIndexBefore {
                    Task { @MainActor in
                        try await Task.sleep(for: .seconds(0.25))
                        model.scrollItem = selectedItem
                    }
                }
            } else {
                model.selectedItem = nil
            }
        }
        model.selectedItems = model.selectedItems.filter { item in
            model.filteredItems.contains(where: { $0.id == item.id })
        }
    }
    
    @MainActor
    func update(model: ItemRowModel) {
        guard let item = find(model: model, inside: true) else { return }
        update(item: item)
    }
    
    @MainActor
    func update(item: ItemRowTreeModel) {
        let parentItem: ItemRowTreeModel?
        if item.model.entryId == nil {
            parentItem = item
        } else {
            parentItem = findParent(selected: item)
        }
        guard let parentItem, parentItem.expanded else { return }
        
        var (children, idChildren): ([ItemRowTreeModel], [UUID: Int]) = ([], [:])
        let childModels = itemControllable.children(for: parentItem.model)
        (children, idChildren) = updateSubList(entries: childModels, items: parentItem.children, idItems: parentItem.idChildren, level: item.level + 1)
        parentItem.children = children
        parentItem.idChildren = idChildren
        let count = children.count
        children.enumerated().forEach { index, child in
            child.isFirst = index == 0
            child.isLast = index == (count - 1)
        }
        resetFilter()
    }
    
    @MainActor
    private func updateSubList(entries: [ItemRowModel], items: [ItemRowTreeModel], idItems: [UUID: Int], level: Int) -> ([ItemRowTreeModel], [UUID: Int]) {
        var idMapper: [UUID: Int] = [:]
        let newItems = entries.enumerated().map { index, newModel in
            var item: ItemRowTreeModel
            if let previousIndex = idItems[newModel.entryId ?? newModel.itemId], previousIndex < items.count {
                item = items[previousIndex]
                if item.model.typeId != newModel.typeId {
                    let editIndex = previousIndex + 1
                    if editIndex < items.count {
                        item = items[editIndex]
                        if item.model != newModel {
                            item = ItemRowTreeModel(id: UUID(), model: newModel, level: level, expanded: false, idChildren: [:])
                        }
                    } else {
                        item = ItemRowTreeModel(id: UUID(), model: newModel, level: level, expanded: false, idChildren: [:])
                    }
                }
            } else {
                item = ItemRowTreeModel(id: UUID(), model: newModel, level: level, expanded: false, idChildren: [:])
            }
            if newModel.typeId != .editor {
                idMapper[newModel.entryId ?? newModel.itemId] = index
            }
            
            if item.expanded {
                var (children, idChildren): ([ItemRowTreeModel], [UUID: Int]) = ([], [:])
                if item.model.entryId != nil {
                    if !item.children.isEmpty {
                        (children, idChildren) = updateSubList(entries: item.children.map { $0.model }, items: item.children, idItems: item.idChildren, level: level + 1)
                    }
                } else {
                    let childModels = itemControllable.children(for: newModel)
                    (children, idChildren) = updateSubList(entries: childModels, items: item.children, idItems: item.idChildren, level: level + 1)
                }
                item.children = children
                item.idChildren = idChildren
            }
            return item
        }
        return (newItems, idMapper)
    }
    
    @MainActor
    func resetSelectedItem() {
        if let item = model.selectedItem {
            model.selectedItem = nil
            model.selectedItems.removeAll(where: { $0.id == item.id })
        }
    }
    
    @MainActor
    func observable(item: ItemRowTreeModel) -> any (ItemDataAccessable & Equatable) {
        guard model.hasChildren && item.expanded && item.model.entryId == nil else {
            return itemControllable.itemOrEmpty(for: UUID())
        }
        return itemControllable.itemOrEmpty(for: item.model.itemId)
    }
}

// MARK: - Filter

public extension ListControllable {
    @MainActor
    var filteredTagSuggestions: [SearchTags] {
        guard model.searchText.starts(with: "@") else { return [] }
        let tagSearch = model.searchText.dropFirst()
        if !tagSearch.isEmpty {
            return itemControllable.itemDataModel.allTags.filter { $0.localizedCaseInsensitiveContains(tagSearch) }.map { SearchTags(tag: $0) }
        }
        return []
    }
    
    @MainActor
    func filter(text: String, selectedTokens: [SearchTags], searchToken: ItemListCategory) {
        var tags: [TagFilterSelection] = selectedTokens.map {
            TagFilterSelection(tag: $0.tag, state: .selected)
        }
        if searchToken != model.categoryTags.first {
            tags.append(TagFilterSelection(tag: "\(searchToken.title)", state: .selected))
        }
        let searchText = text.starts(with: "@") ? String(text.dropFirst()) : text
        model.filteredItems = filterChildren(search: searchText, isHidden: model.isHiddenItems, filterTags: tags, items: model.unfilteredItems)

        if model.lastSearchText != text {
            model.cacheItemList.reset(search: text)
        }
        let textCount = searchText.count
        if model.lastSearchText.count < textCount && textCount > 0 && textCount <= 4 {
            for item in model.filteredItems {
                if itemControllable.nameSync(itemId: item.model.itemId).starts(with: text) {
                    model.scrollItem = item
                    break
                }
            }
            model.lastSearchText = text
        } else {
            model.lastSearchText = text
        }
    }
    
    @MainActor
    func toggleHide() {
        model.isHiddenItems.toggle()
        resetFilter()
    }
    
    @MainActor
    func resetFilter() {
        filter(text: model.searchText, selectedTokens: model.selectedTokens, searchToken: model.searchToken)
    }
    
    @MainActor
    private func filterChildren(search: String, isHidden: Bool, filterTags: [TagFilterSelection], items: [ItemRowTreeModel], isRoot: Bool = true) -> [ItemRowTreeModel] {
        var result: [ItemRowTreeModel] = []
        for item in items {
            if let filterModel = model.filterModel, isRoot && filterModel != item.model {
                continue
            }
            let filterState = itemControllable.filter(model: item.model, search: search, isHidden: isHidden, filterTags: filterTags, enableFilterChildren: model.filterModel == item.model)
            if filterState != .notMatch {
                if !(isRoot == false && model.hideChildrenHeader && item.model.entryId == nil) {
                    result.append(item)
                }
            }

            if (isRoot || model.filterModel != nil) && (filterState == .onlyChildrenMatch || filterState == .childrenMatch) && item.expanded == false {
                if item.model.entryId == nil {
                    toggleExpanded(item: item, withResetFilters: true)
                } else {
                    if let childItem = itemControllable.childrenTree(for: item.model) {
                        toggle(parent: item, child: childItem)
                    }
                }
            }

            var children: [ItemRowTreeModel] = []
            if item.expanded == true {
                children = filterChildren(search: search, isHidden: isHidden, filterTags: filterTags, items: item.children, isRoot: false)
                if filterState == .notMatch && model.hideChildrenHeader == false && item.model.entryId == nil {
                    result.append(item)
                }
                result.append(contentsOf: children)
            }
        }
        return result
    }
}

// MARK: - Selections

extension ListControllable {
    @MainActor
    func name(for item: ItemRowTreeModel) async -> String {
        await itemControllable.name(model: item.model)
    }
    
    func usedLinks(for item: ItemRowTreeModel) async -> [EffectedItemModel] {
        await itemControllable.usedLinks(for: item.model)
    }
    
    @MainActor
    private func find(model: ItemRowModel, inside: Bool = false) -> ItemRowTreeModel? {
        var result: ItemRowTreeModel?
        for item in self.model.unfilteredItems {
            if inside {
                result = findInside(tree: item, model: model)
            } else {
                if item.model == model && item.level == 0 {
                    result = item
                }
            }
            if result != nil {
                break
            }
        }
        return result
    }
    
    @MainActor
    private func findInside(tree: ItemRowTreeModel, model: ItemRowModel) -> ItemRowTreeModel? {
        if tree.model == model {
            return tree
        } else {
            for child in tree.children {
                let result = findInside(tree: child, model: model)
                if result != nil {
                    return result
                }
            }
        }
        return nil
    }
    
    @MainActor
    private func findIndex(selected: ItemRowTreeModel) -> Int? {
        let (result, found) = findIndexChild(selected: selected, in: model.filteredItems)
        if found {
            return result
        }
        return nil
    }
    
    @MainActor
    private func findIndexChild(selected: ItemRowTreeModel, in items: [ItemRowTreeModel]) -> (Int, Bool) {
        var result = 0
        for item in items {
            result += 1
            if selected == item {
                return (result, true)
            }
            let (subResult, found) = findIndexChild(selected: selected, in: item.children)
            result += subResult
            if found {
                return (result, true)
            }
        }
        return (result, false)
    }

    @MainActor
    private func findParentIndex(selected: ItemRowTreeModel, in items: [ItemRowTreeModel]) -> ItemRowTreeModel? {
        for item in items {
            if selected == item {
                return item
            }
            if let foundItem = findParentIndex(selected: selected, in: item.children) {
                return foundItem.model.itemId == item.model.itemId ? item : foundItem
            }
        }
        return nil
    }

    @MainActor
    private func findParent(selected: ItemRowTreeModel) -> ItemRowTreeModel? {
        findParentIndex(selected: selected, in: model.filteredItems)
    }
        
    @MainActor
    func resetSelectedItem(selection newSelected: Set<ItemRowTreeModel>, filterEntries: Bool = false, disableSelection: Bool) {
        let filterSelected = filterEntries ? newSelected.filter { $0.model.entryId == nil } : newSelected
        guard filterSelected != Set(model.selectedItems) else { return }
        
        let existingSelected = filterSelected.filter { selectedId in
            model.filteredItems.contains { $0 == selectedId }
        }
        var newSelection = model.selectedItems.filter { existingSelected.contains($0) }
        
        var diffSelection = Array(existingSelected.filter { !newSelection.contains($0) })
        diffSelection.sort { a, b in
            guard let itemA = findIndex(selected: a),
                  let itemB = findIndex(selected: b) else { return false }
            return itemA < itemB
        }
        newSelection.append(contentsOf: diffSelection)

        let applySelection = newSelection
        model.selectedItems <=> applySelection

        if let last = model.selectedItems.last, last.model.entryId != nil {
            model.gameSelectedItem <=> last
        }
        guard !disableSelection else { return }
        model.selectedItem <=> model.selectedItems.last
    }
    
    @MainActor
    func setSelectedItem(selection newSelected: ItemRowTreeModel) {
        if let selectionMode = model.selectionMode {
            selectionMode.toggle(newSelected.model, false)
            model.selectedItems <=> selectionMode.selected().compactMap { find(model: $0, inside: true) }
        } else {
            model.selectedItems <=> [newSelected]
        }
        guard model.selectionMode == nil else { return }
        model.selectedItem <=> model.selectedItems.last
    }
    
    @MainActor
    func selectItem(matching characters: String) -> Bool {
        var first: ItemRowTreeModel? = nil
        for item in model.filteredItems {
            if itemControllable.start(model: item.model, with: characters) {
                first = item
                break;
            }
        }
        guard let first else { return false }
        model.selectedItems = [first]
        model.selectedItem = first
        model.scrollItem = first
        return true
    }
    
    @MainActor
    func selectItem(directionUp: Bool) {
        guard let selectedItem = model.selectedItem, let firstIndex = model.filteredItems.firstIndex(where: { $0.id == selectedItem.id }) else { return }
        let selectedIndex = directionUp ? model.filteredItems.index(before: firstIndex) : model.filteredItems.index(after: firstIndex)
        let nextItem = model.filteredItems[selectedIndex]
        model.selectedItems = [nextItem]
        model.selectedItem = nextItem
        model.scrollItem = nextItem
    }
    
    @MainActor
    public func selection(for selection: Set<ItemRowTreeModel>, filterEntries: Bool = false) -> ([ItemRowModel], ItemRowModel?) {
        var models = model.selectedItems.compactMap { ($0.model.typeId == itemControllable.itemDataModel.networkModule && (!filterEntries || $0.model.entryId == nil)) ? $0.model : nil }
        
        let currentSelection = selection.compactMap { $0.model.typeId == itemControllable.itemDataModel.networkModule ? $0.model : nil }
        let model = currentSelection.count == 1 ? currentSelection[0] : models.last
        
        models = models.filter { $0 != model }
        return (models, model)
    }
    
    @MainActor
    func selected(for selection: Set<ItemRowTreeModel>) -> ItemRowTreeModel? {
        let items = model.selectedItems.compactMap { $0.model.typeId == itemControllable.itemDataModel.networkModule && $0.model.entryId == nil ? $0 : nil }
        
        let currentSelection = selection.compactMap { $0.model.typeId == itemControllable.itemDataModel.networkModule && $0.model.entryId == nil ? $0 : nil }
        
        return currentSelection.count == 1 ? currentSelection[0] : items.last
    }
    
    @MainActor
    public func setFocusItem(model row: ItemRowModel?) {
        self.model.filterModel = row
        if let row, let item = find(model: row), !item.expanded {
            toggleExpanded(item: item)
        }
        resetFilter()
    }

    @MainActor
    public func setSearchFilter(text: String) {
        model.searchText = text
        resetFilter()
    }

    @MainActor
    public func setSelectedItems(models: [ItemRowModel]) {
        model.selectedItems = models.compactMap { find(model: $0, inside: true) }
    }
    
    @MainActor
    public func setSelectedItem(model row: ItemRowModel) {
        if let item = find(model: row) {
            model.selectedItem = item
            model.selectedItems = [item]
            if !item.expanded {
                toggleExpanded(item: item)
            }
            Task { @MainActor in
                try await Task.sleep(for: .seconds(1))
                model.scrollItem = item
            }
        }
        resetFilter()
    }
    
    @MainActor
    public func setSelection(selectionId: UUID = UUID(), onlyItems: Bool, onlyEntries: Bool, filter: ItemListCategory, isHidden: Bool, focus: UUID?, mode: SelectionMode) {
        
        model.selectionMode = mode
        model.searchToken = filter
        model.isHiddenItems = isHidden
        model.onlyItems = onlyItems
        model.onlyEntries = onlyEntries
        update(models: itemControllable.itemDataModel.items.map { ItemRowModel(itemId: $0, typeId: itemControllable.itemDataModel.networkModule) })
        var rootItem: ItemRowTreeModel? = nil
        if let focus {
            model.filterModel = ItemRowModel(itemId: focus, typeId: itemControllable.itemDataModel.networkModule)
            if let parentItem = find(model: ItemRowModel(itemId: focus, typeId: itemControllable.itemDataModel.networkModule)) {
                toggleChildren(item: parentItem)
                rootItem = parentItem
            }
        }
        let selectionModel = mode.selected()
        for model in selectionModel {
            guard model.entryId != nil else { continue }
            if let rootItem {
                let modelTree = [rootItem.model] + itemControllable.itemTree(from: rootItem.model, to: model)
                modelTree.forEach {
                    if let parentItem = findInside(tree: rootItem, model: $0) {
                        if !parentItem.expanded {
                            toggleParent(parent: parentItem, item: model)
                        }
                    }
                }
            } else {
                let modelTree = itemControllable.itemTree(from: nil, to: model)
                for item in modelTree {
                    let model = ItemRowModel(itemId: item.itemId, entryId: nil, typeId: item.typeId)
                    if let parentItem = find(model: model) {
                        if !parentItem.expanded {
                            toggleChildren(item: parentItem)
                        }
                    }
                }
            }
        }
        let items = selectionModel.compactMap { find(model: $0, inside: true) }
        model.selectedItems = items
        resetFilter()
    }
    
    @MainActor
    func allSelected(for selection: Set<ItemRowTreeModel>) -> [ItemRowTreeModel] {
        var items = model.selectedItems.compactMap { $0.model.typeId == itemControllable.itemDataModel.networkModule ? $0 : nil}
        
        let currentSelection = selection.compactMap { $0.model.typeId == itemControllable.itemDataModel.networkModule ? $0 : nil }
        if currentSelection.count == 1 && !items.contains(currentSelection[0]) {
            items.append(currentSelection[0])
        }
        
        return items
    }
    
    @MainActor
    func resetAction(selection newSelected: Set<ItemRowTreeModel>) {
        let filterSelected = newSelected.filter { $0.model.entryId == nil }
        guard filterSelected != Set(model.selectedItems) else {
            model.actionSelection = model.selectedItems
            return
        }
        
        let existingSelected = filterSelected.filter { selectedId in
            model.filteredItems.contains { $0 == selectedId }
        }
        var newSelection = model.selectedItems.filter { existingSelected.contains($0) }
        
        var diffSelection = Array(existingSelected.filter { !newSelection.contains($0) })
        diffSelection.sort { a, b in
            guard let itemA = findIndex(selected: a), let itemB = findIndex(selected: b) else { return false }
            return itemA < itemB
        }
        newSelection.append(contentsOf: diffSelection)

        let applySelection = newSelection
        model.actionSelection = applySelection
    }
}

// MARK: - Actions

extension ListControllable {
    public func addNew() async {
        let row = await addNewWithoutEdit()
        selectAndScroll(to: row)
    }
    
    @MainActor
    public func addNewWithoutEdit() async -> ItemRowModel {
        let type = (model.searchToken.title != model.categoryTags.first?.title) ? model.searchToken : nil
        return await itemControllable.addNew(type: type?.rawValue)
    }
    
    public func selectAndScroll(to row: ItemRowModel) {
        Task { @MainActor in
            try await Task.sleep(for: .seconds(0.3))
            guard let item = find(model: row) else { return }
            model.selectedItem = item
            model.selectedItems = [item]
            Task { @MainActor in
                try await Task.sleep(for: .seconds(0.2))
                model.scrollItem = item
                model.activeEdit = true
            }
        }
    }
    
    @MainActor
    private func titleName(for selection: Set<ItemRowTreeModel>, filterEntries: Bool = false) -> (String, Int?) {
        let (models, model) = self.selection(for: selection, filterEntries: filterEntries)
        guard let model else { return ("", nil) }
        let name = itemControllable.nameSync(model: model)
        let count = models.count
        if count == 0 {
            return (name, nil)
        }
        return (name, count)
    }
    
    @MainActor
    func copyTitle(for selection: Set<ItemRowTreeModel>) -> LocalizedStringKey {
        let (name, count) = titleName(for: selection, filterEntries: true)
        if let count {
            return "Copy \(name) and \(count) item"
        }
        return "Copy \(name)"
    }
    
    @MainActor
    public func copyItems(selection: Set<ItemRowTreeModel>) async {
        let (models, rootModel) = self.selection(for: selection, filterEntries: true)
        if let rootModel {
            await itemControllable.duplicate(model: rootModel)
        }
        for model in models {
            await itemControllable.duplicate(model: model)
        }
    }
    
    @MainActor
    func createLinkTitle(for selection: Set<ItemRowTreeModel>) -> LocalizedStringKey {
        let (name, count) = titleName(for: selection)
        if let count {
            return "Link \(name) and \(count) item"
        }
        return "Link \(name)"
        
    }
    
    @MainActor
    func createLinks(selection: Set<ItemRowTreeModel>) async {
        let allSelection = allSelected(for: selection)
        var links: [String] = []
        for selected in allSelection {
            links.append(itemControllable.createLink(model: selected.model))
        }
        let linkText = links.joined(separator: " ")
#if os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(linkText, forType: .string)
#elseif !os(tvOS)
        let pasteboard = UIPasteboard.general
        pasteboard.string = linkText
#endif
    }
    
    @MainActor
    func selectionCount(for selection: Set<ItemRowTreeModel>, filterEntries: Bool) -> Int {
        let (models, model) = self.selection(for: selection, filterEntries: filterEntries)
        if model == nil || model?.entryId != nil {
            return 0
        }
        return models.count + 1
    }
    
    @MainActor
    func deleteTitle(for selection: Set<ItemRowTreeModel>) -> LocalizedStringKey {
        let (name, count) = titleName(for: selection, filterEntries: true)
        if let count {
            return "Delete \(name) and \(count) item"
        }
        return "Delete \(name)"
        
    }
    
    @MainActor
    func deleteItems(selection: Set<ItemRowTreeModel>) async {
        for item in selection {
            if model.selectedItem == item {
                resetSelectedItem()
            }
            if let index = model.selectedItems.firstIndex(where: { $0.id == item.id }) {
                model.selectedItems.remove(at: index)
            }
            if model.scrollItem == item {
                model.scrollItem = nil
            }
            if model.filterModel == item.model {
                model.filterModel = nil
            }
            if let index = model.unfilteredItems.firstIndex(where: { $0.id == item.id }) {
                model.unfilteredItems.remove(at: index)
                var updatedIds: [UUID: Int] = [:]
                for (index, item) in model.unfilteredItems.enumerated() {
                    updatedIds[item.model.itemId] = index
                }
                model.idItems = updatedIds
            }
            await itemControllable.delete(model: item.model)
        }
    }
    
    @MainActor
    func exportTitle(for selection: Set<ItemRowTreeModel>) -> LocalizedStringKey {
        let (name, count) = titleName(for: selection, filterEntries: true)
        if let count {
            return "Export \(name) and \(count) item"
        }
        return "Export \(name)"
        
    }
    
    @MainActor
    func focusTitle(for selection: Set<ItemRowTreeModel>) -> LocalizedStringKey {
        guard let item = self.selected(for: selection) else { return "Focus" }
        let name = itemControllable.nameSync(model: item.model)
        if model.filterModel == item.model {
            return "Unfocus \"\(name)\""
        }
        return "Focus \"\(name)\""
    }
    
    @MainActor
    func focus(for selection: Set<ItemRowTreeModel>) async {
        guard let item = self.selected(for: selection) else { return }
        if model.filterModel == item.model {
            model.filterModel = nil
        } else {
            model.filterModel = item.model
        }
        resetFilter()
    }
    
    @MainActor
    func generateTitle(for selection: Set<ItemRowTreeModel>) -> LocalizedStringKey {
        guard let item = self.selected(for: selection) else { return "Generate" }
        let name = itemControllable.nameSync(model: item.model)
        return "Generate item for \"\(name)\""
    }
    
    @MainActor
    func isGroupDisabled(for selection: Set<ItemRowTreeModel>) -> Bool {
        let (_, itemId) = self.selection(for: selection)
        return itemId == nil
    }
    
    @MainActor
    func groupEditTitle(for selection: Set<ItemRowTreeModel>) -> LocalizedStringKey {
        let (name, count) = titleName(for: selection, filterEntries: true)
        if let count {
            return "Edit Group \(name) and \(count) item"
        }
        return "Edit Group \(name)"
    }
    
    @MainActor
    func groupTitle(for selection: Set<ItemRowTreeModel>) -> LocalizedStringKey {
        let (models, rootModel) = self.selection(for: selection)
        guard let rootModel, let item = itemControllable.itemSync(for: rootModel.itemId) else { return "Group" }
        let count = models.count
        if item.entries.isEmpty {
            if count == 0 {
                return "Group \"\(item.name)\""
            }
            return "Group \"\(item.name)\" with \(count) item"
        }
        return "Ungroup \"\(item.name)\" into \(item.entries.count) item"
    }
}

// MARK: - Children / Expand / Collapse

public extension ListControllable {
    @MainActor
    func toggleExpanded(item: ItemRowTreeModel, withResetFilters: Bool = true) {
        toggleChildren(item: item, withResetFilters: withResetFilters)
        if withResetFilters {
            resetFilter()
        }
    }
    
    @MainActor
    func toggle(parent: ItemRowTreeModel, child: ItemRowModel, multipleIds: [ItemRowModel]? = nil, expandNext: Bool = true) {
        toggleParent(parent: parent, item: child, multipleIds: multipleIds, expandNext: expandNext)
        resetFilter()
    }
    
    @MainActor
    func toggleExpanded(model: ItemRowModel, to state: Bool) {
        guard let item = find(model: model, inside: true), item.expanded != state else { return }
        toggleChildren(item: item)
        resetFilter()
    }
    
    @MainActor
    func addSubTables(child: ItemRowModel, entryId: UUID, nextItems: [ItemRowModel]) {
        guard let parent = find(model: child, inside: true) else { return }
        guard !nextItems.isEmpty else {
            if parent.model.entryId == nil {
                toggleExpanded(item: parent)
            }
            return
        }
        
        guard let childParent = parent.children.first(where: { $0.model.entryId == entryId }) else { return }
        toggle(parent: childParent, child: child, multipleIds: nextItems, expandNext: true)
    }
    
    @MainActor
    func removeSubTables(from child: ItemRowModel) {
        let parentModel = ItemRowModel(itemId: child.itemId, typeId: child.typeId)
        guard let parent = find(model: parentModel, inside: true), parent.expanded else { return }
        toggle(parent: parent, child: child, multipleIds: [], expandNext: false)
    }
    
    @MainActor
    private func toggleParent(parent: ItemRowTreeModel, item: ItemRowModel, multipleIds: [ItemRowModel]? = nil, expandNext: Bool = true) {
        var updatedItem = parent
        
        if let entryId = item.entryId, let index = updatedItem.idChildren[entryId] {
            updatedItem = updatedItem.children[index]
        }
        updatedItem.expanded.toggle()
        
        if updatedItem.expanded {
            updatedItem.children = []
            updatedItem.idChildren = [:]
            
            let listItems = multipleIds ?? [item]
            listItems.enumerated().forEach { index, model in
                let children = expandNext ?
                createExpandedChildren(model: model, level: updatedItem.level + 2) : ([], [:])
                
                let newItem = ItemRowTreeModel(id: UUID(), model: model, level: updatedItem.level + 1, expanded: expandNext, children: children.0, idChildren: children.1)
                
                updatedItem.children.append(newItem)
                updatedItem.idChildren[model.itemId] = index
            }
        } else {
            updatedItem.children = []
            updatedItem.idChildren = [:]
        }
    }
    
    @MainActor
    private func toggleChildren(item: ItemRowTreeModel, withResetFilters: Bool = true) {
        item.expanded.toggle()
        
        if item.expanded {
            let children = createExpandedChildren(model: item.model, level: item.level + 1)
            if children.0.isEmpty {
                item.expanded = false
            } else {
                item.children = children.0
                item.idChildren = children.1
            }
        } else {
            removeListCache(children: item.children)
            item.children = []
            item.idChildren = [:]
        }
        if withResetFilters {
            resetFilter()
        }
    }
    
    @MainActor
    private func removeListCache(children: [ItemRowTreeModel]) {
        for child in children {
            removeListCache(children: child.children)
            model.cacheItemList.cache[child.id] = nil
        }
    }
    
    @MainActor
    private func createExpandedChildren(model: ItemRowModel, level: Int) -> ([ItemRowTreeModel], [UUID: Int]) {
        let childModels = itemControllable.children(for: model)
        var idMapper: [UUID: Int] = [:]
        let entries = childModels.enumerated().map { index, childModel in
            idMapper[childModel.entryId ?? childModel.itemId] = index
            return ItemRowTreeModel(id: UUID(), model: childModel, level: level, expanded: false, children: [], idChildren: [:])
        }
        if entries.count > 0 {
            entries[0].isFirst = true
            entries[entries.count - 1].isLast = true
        }
        return (entries, idMapper)
    }
}
