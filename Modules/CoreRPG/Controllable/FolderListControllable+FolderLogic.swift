// @copyright André Trettin

import Foundation

// MARK: Folder Logic

extension FolderListControllable {
    /// Fully synchronous — `loadChildrenViaSearch` uses `syncExpandResults` (pure `itemSync` map).
    /// The old `async` + `await performSearch()` else-branch was dead code: reaching
    /// `canOpen=false && children=[]` requires `wasExplicitlyClosed=true`, which in turn
    /// requires a prior open that already populated `children`. See sync-concurrency analysis.
    func toggleFolder(item: FolderListItemModel) {
        if item.isOpen {
            item.isOpen = false
            item.lastIsOpen = false
            item.wasExplicitlyClosed = true
            resetFilter()
        } else {
            item.isOpen = true
            item.lastIsOpen = true
            item.wasExplicitlyClosed = false
            if item.children.isEmpty && item.canOpen {
                loadChildrenViaSearch(for: item)
            }
            resetFilter()
        }
    }

    func toggleParentFolder(item: FolderListItemModel) {
        guard let parentId = item.parentId, let parentItem = listModel.cacheListModels[parentId] else { return }
        parentItem.isOpen.toggle()
        parentItem.lastIsOpen = parentItem.isOpen  // Mirror user's explicit choice
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

    /// Toggles the selected folder without changing list-column focus.
    /// Returns whether the selected row supported the action.
    @discardableResult
    func toggleSelectedFolder() -> Bool {
        toggleFolder(itemId: listModel.selectedItemId)
    }

    /// Toggles a visible folder row. Both an already-open folder and a closed
    /// folder with loadable/cached children support the action.
    @discardableResult
    func toggleFolder(itemId: UUID?) -> Bool {
        guard let item = folderItem(itemId: itemId),
              canToggleFolder(itemId: itemId) else { return false }
        toggleFolder(item: item)
        listModel.scrollId = item.id
        listModel.recordVisibleScrollPosition(item.id)
        return true
    }

    func canToggleFolder(itemId: UUID?) -> Bool {
        guard let item = folderItem(itemId: itemId) else { return false }
        return item.isOpen
            || item.canOpen
            || item.wasExplicitlyClosed
            || !item.children.isEmpty
    }

    func isFolderOpen(itemId: UUID?) -> Bool {
        folderItem(itemId: itemId)?.isOpen ?? false
    }

    /// Closes the nearest open parent folder of `itemId` and selects that parent folder.
    /// Closes it the way the chevron does: setting only `isOpen` left the children listed, and
    /// the next rebuild reopened the folder from `lastIsOpen`. See CODE_AUDIT_Folder §5.13.
    func closeParentFolder(of itemId: UUID) {
        guard let item = listModel.list.first(where: { $0.source.itemId == itemId }) else { return }
        guard let parentId = item.parentId, let parentItem = listModel.cacheListModels[parentId] else { return }
        if parentItem.isOpen {
            toggleFolder(item: parentItem)
        }
        listModel.selected = parentId
        listModel.listSelection = Set(arrayLiteral: parentId)
        listModel.scrollId = parentId
        listModel.navigationModel.selectedItemId = parentItem.source.itemId
    }

    /// Opens `itemId` if it is a closed folder that can be expanded or was explicitly closed.
    func openFolder(itemId: UUID) {
        guard let item = listModel.list.first(where: { $0.source.itemId == itemId }),
              (item.canOpen || item.wasExplicitlyClosed) && !item.isOpen else { return }
        toggleFolder(item: item)
    }

    /// Returns true if `itemId` is a closed item that can be expanded or was explicitly closed.
    func canOpenFolder(itemId: UUID?) -> Bool {
        guard let itemId,
              let item = listModel.list.first(where: { $0.source.itemId == itemId }) else { return false }
        return (item.canOpen || item.wasExplicitlyClosed) && !item.isOpen
    }

    /// Returns true if `itemId` has an open parent folder in the visible tree.
    func hasParentFolder(itemId: UUID?) -> Bool {
        guard let itemId,
              let item = listModel.list.first(where: { $0.source.itemId == itemId }),
              let parentId = item.parentId, let parentItem = listModel.cacheListModels[parentId] else { return false }
        return parentItem.isOpen
    }

    private func folderItem(itemId: UUID?) -> FolderListItemModel? {
        guard let itemId else { return nil }
        return listModel.list.first {
            $0.id == itemId || $0.source.itemId == itemId
        }
    }
}
