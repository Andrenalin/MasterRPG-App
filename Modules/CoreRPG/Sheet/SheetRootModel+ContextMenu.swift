// @copyright André Trettin

import SwiftUI

extension SheetRootModel {
    // MARK: - Context menu actions

    func duplicateEntry(entryModel: SheetModel, in parentModel: SheetModel) {
        guard let entryId = entryModel.source.entryId,
              let editable = entryDataEditable(for: entryModel.source),
              let newId = editable.copy(itemId: entryModel.source.itemId, entryId: entryId, forceSave: persistsEdits) else { return }
        editorModel.setEdit(source: ItemRowModel(itemId: entryModel.source.itemId, entryId: newId, typeId: entryModel.source.typeId))
        updateParent(parentModel)
    }

    func moveEntry(entryModel: SheetModel, in parentModel: SheetModel, up: Bool) {
        guard let editable = entryDataEditable(for: entryModel.source),
              let index = parentModel.entries.firstIndex(where: { entry in
                  entry.source.itemId == entryModel.source.itemId &&
                  entry.source.entryId == entryModel.source.entryId
              }) else { return }
        // The neighbour is the previous or next row that is an entry: linked sheets share
        // `entries` but have no entry id and are not part of the stored order.
        // See CODE_AUDIT_26 §5.63.
        let entryIndices = parentModel.entries.indices.filter { parentModel.entries[$0].source.entryId != nil }
        guard let position = entryIndices.firstIndex(of: index) else { return }
        let neighbourPosition = up ? position - 1 : position + 1
        guard entryIndices.indices.contains(neighbourPosition) else { return }
        let neighbourIndex = entryIndices[neighbourPosition]
        let newIndex = up ? neighbourIndex : neighbourIndex + 1
        parentModel.entries.move(fromOffsets: IndexSet(integer: index), toOffset: newIndex)
        editable.move(itemId: parentModel.source.itemId, entryIds: parentModel.entries.compactMap { $0.source.entryId }, forceSave: persistsEdits)
        if !searchText.isEmpty {
            updateFilteredEntries()
        }
        updateParent(parentModel)
    }

    func reorderEntry(from sourceIndex: Int, to targetIndex: Int, in parentModel: SheetModel) {
        guard sourceIndex != targetIndex,
              let editable = entryDataEditable(for: parentModel.source),
              sourceIndex >= 0,
              sourceIndex < parentModel.entries.count,
              targetIndex >= 0,
              targetIndex < parentModel.entries.count else { return }

        let entry = parentModel.entries[sourceIndex]
        parentModel.entries.remove(at: sourceIndex)
        // Removing `sourceIndex` shifts every later index down by one, so the forward
        // (sourceIndex < targetIndex) direction needs the -1 compensation to land the
        // entry directly before the target; the backward direction doesn't, since the
        // removal happened after `targetIndex` and never shifted it. See CODE_AUDIT_Sheet §5.1.
        let insertIndex = sourceIndex < targetIndex ? targetIndex - 1 : targetIndex
        parentModel.entries.insert(entry, at: insertIndex)

        editable.move(itemId: parentModel.source.itemId, entryIds: parentModel.entries.compactMap { $0.source.entryId }, forceSave: persistsEdits)
        if !searchText.isEmpty {
            updateFilteredEntries()
        }
        updateParent(parentModel)
    }

    func moveEntry(fromItemId: UUID, entryId: UUID, toItemId: UUID, afterEntry: SheetModel) {
        guard let sourceEditable = entryDataEditable(for: ItemRowModel(itemId: fromItemId, typeId: afterEntry.source.typeId)) else { return }

        // Move the entry from source item to target item
        let success = sourceEditable.move(itemId: fromItemId, entryId: entryId, into: ItemRowModel(itemId: toItemId, typeId: afterEntry.source.typeId), forceSave: persistsEdits)

        guard success else { return }

        // Update the sheet models to reflect the changes
        updateFromRoot()
    }

    func handleDrop<LinkType: LinkDataTransferable>(items: [LinkType], targetEntry: SheetModel, parentModel: SheetModel) -> Bool {
        guard let droppedItem = items.first else { return false }

        if droppedItem.isMove {
            // ===== MOVE: Entry being moved (within same item or across items in same module) =====

            // Only allow moves within same module
            guard droppedItem.module == targetEntry.source.typeId else {
                return false
            }

            // Don't allow dropping on inline entries (like dice, photo, etc.)
            guard targetEntry.sheetType == .item || targetEntry.sheetType == .group else {
                return false
            }

            guard let draggedEntryId = droppedItem.entryId else {
                return false
            }

            // Check if this is a move within the same parent item (reorder)
            if droppedItem.itemId == parentModel.source.itemId,
               let draggedIndex = parentModel.entries.firstIndex(where: { $0.source.entryId == draggedEntryId }),
               let targetIndex = parentModel.entries.firstIndex(where: { entry in
                   entry.source.itemId == targetEntry.source.itemId &&
                   entry.source.entryId == targetEntry.source.entryId
               }),
               draggedIndex != targetIndex {
                // Reorder within same parent
                withAnimation {
                    reorderEntry(from: draggedIndex, to: targetIndex, in: parentModel)
                }
                return true
            }

            // Otherwise, move entry from one item to another (cross-item move)
            if droppedItem.itemId != targetEntry.source.itemId {
                withAnimation {
                    moveEntry(
                        fromItemId: droppedItem.itemId,
                        entryId: draggedEntryId,
                        toItemId: targetEntry.source.itemId,
                        afterEntry: targetEntry
                    )
                }
                return true
            }

            return false

        } else {
            // ===== LINK DROP: From inspector or viewer mode =====

            // Only allow link drops on item entries (not groups, not inline entries)
            guard targetEntry.sheetType == .item else {
                return false
            }

            items.forEach {
                addLink(link: $0.name, module: $0.module, itemId: $0.itemId, entryId: $0.entryId, to: targetEntry, in: parentModel)
            }
            return true
        }
    }

    func groupFolders(for entryModel: SheetModel) -> [FolderRepresentable] {
        guard let entryId = entryModel.source.entryId,
              let editable = entryDataEditable(for: entryModel.source) else { return [] }
        return editable.groupFolders(itemId: entryModel.source.itemId, sourceEntryId: entryId)
    }

    func moveEntry(_ entryModel: SheetModel, in parentModel: SheetModel, into folder: FolderRepresentable) {
        guard let entryId = entryModel.source.entryId,
              let editable = entryDataEditable(for: entryModel.source) else { return }
        editable.move(itemId: entryModel.source.itemId, sourceEntryId: entryId, into: folder, forceSave: persistsEdits)
        pendingGroupMoveTask?.cancel()
        pendingGroupMoveTask = delayedTask(.settleDelay) { [self] in
            updateParent(parentModel)
        }
    }

    func parentGroup(for entryModel: SheetModel) -> FolderRepresentable? {
        entryDataEditable(for: entryModel.source)?.parentFolder(itemId: entryModel.source.itemId)
    }

    /// Whether `parentGroup(for:)`'s result is a true value-group parent this
    /// entry can move back out to — see `EntryDataEditable.isValueGroupParent(itemId:)`.
    func canMoveOutOfGroup(for entryModel: SheetModel) -> Bool {
        entryDataEditable(for: entryModel.source)?.isValueGroupParent(itemId: entryModel.source.itemId) ?? true
    }

    func moveEntryOutOfGroup(_ entryModel: SheetModel, in parentModel: SheetModel, parent: FolderRepresentable) {
        guard let entryId = entryModel.source.entryId,
              let editable = entryDataEditable(for: entryModel.source) else { return }
        editable.moveOutOfGroup(itemId: entryModel.source.itemId, sourceEntryId: entryId, parent: parent, forceSave: persistsEdits)
        pendingGroupMoveTask?.cancel()
        pendingGroupMoveTask = delayedTask(.settleDelay) { [self] in
            updateParent(parentModel)
        }
    }

    func addLink(link: String, module: NetworkModules, itemId: UUID, entryId: UUID?, to destination: SheetModel, in parentModel: SheetModel) {
        guard let editable = entryDataEditable(for: destination.source),
              let destinationEntryId = destination.source.entryId else { return }
        editable.add(link: link, module: module, itemId: itemId, entryId: entryId, destinationItemId: destination.source.itemId, destinationEntryId: destinationEntryId)
        updateParent(parentModel)
    }
}
