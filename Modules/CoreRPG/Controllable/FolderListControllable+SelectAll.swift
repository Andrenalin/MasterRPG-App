// @copyright André Trettin

import Foundation

// MARK: Select All / Select None

extension FolderListControllable {
    /// Select All in selection mode.
    ///
    /// When `anchorRowId` (the row the menu was opened on, or the keyboard row) is a folder or
    /// collection of the root list, it selects the content of that folder or collection:
    /// - folder mode: it opens the folder first, so the rows exist, and selects the rows under it.
    /// - list mode: the rows of the items the folder or collection holds.
    /// An empty folder keeps the selection as it is. Everywhere else it selects every row of
    /// `scopedModel`, which in a folder's own list is every item in it. Call it with `listModel` or
    /// the scoped detail model (see `scopedListModel(parentModel:)`).
    func selectAll(in scopedModel: FolderListModel, anchorRowId: UUID?) {
        scopedModel.endRangeSelection()
        guard let row = selectAllFolderRow(in: scopedModel, anchorRowId: anchorRowId) else {
            scopedModel.selectAllRows()
            return
        }
        let content: [UUID]
        if listDisplayModel.isFolderMode {
            if !row.isOpen, canToggleFolder(itemId: row.id) {
                toggleFolder(item: row)
            }
            content = listModel.childRowIds(of: row.id)
        } else {
            content = contentRowIds(ofFolderItem: row.source.itemId)
        }
        guard !content.isEmpty else { return }
        listModel.listSelection = Set(content)
    }

    /// The folder or collection row whose content Select All selects: only in the root list, and
    /// only when `anchorRowId` (a row id or an item id) is such a row. `nil` means Select All
    /// selects every row. The menus use it to name the folder: "Select All in <name>".
    func selectAllFolderRow(in scopedModel: FolderListModel, anchorRowId: UUID?) -> FolderListItemModel? {
        guard scopedModel === listModel,
              let anchorRowId,
              let row = listModel.row(id: anchorRowId) ?? listModel.row(itemId: anchorRowId),
              isFolderLikeRow(row) else {
            return nil
        }
        return row
    }

    /// The name of `selectAllFolderRow`, for "Select All in <name>".
    func selectAllFolderName(in scopedModel: FolderListModel, anchorRowId: UUID?) -> String? {
        selectAllFolderRow(in: scopedModel, anchorRowId: anchorRowId)?.model?.name
    }

    /// The rows that show an item the folder or collection holds (the flat list mode has no tree).
    private func contentRowIds(ofFolderItem folderItemId: UUID) -> [UUID] {
        guard let folder = itemControllable.itemSync(for: folderItemId) else { return [] }
        let memberIds = Set(folder.entries.map(\.childId))
        return listModel.list.filter { memberIds.contains($0.source.itemId) }.map(\.id)
    }

    private func isFolderLikeRow(_ row: FolderListItemModel) -> Bool {
        if listDisplayModel.isFolderMode, canToggleFolder(itemId: row.id) {
            return true
        }
        return row.model?.specialCategory == true
    }

    /// Select None in selection mode.
    func selectNone(in scopedModel: FolderListModel) {
        scopedModel.selectNoRows()
    }
}
