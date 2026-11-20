// @copyright André Trettin

import Foundation

/// An entry that can stand for a group: a hidden item of the same module whose own entries are
/// shown inside the entry (Adventure's `adventureId`, Character's `valueId`).
public protocol GroupableEntry: EntryDataAccessible {
    var groupItemId: UUID? { get set }
}

/// The group functions Adventure and Character carried as line-for-line copies.
/// See CODE_AUDIT_Folder §9.9.
public extension EntryDataEditable where Model: GroupableModel, Model.Entry: GroupableEntry {
    @MainActor func addNewGroup(itemId: UUID) async -> UUID {
        let groupId = await itemControllable.addNew(type: .item)
        reset(hidden: true, itemId: groupId)
        guard var group = editModel(for: groupId) else { return groupId }
        group.groupId = itemId
        save(updated: group, message: String(localized: "prepare group", bundle: .module))
        var entry = Model.Entry.empty
        entry.name = group.name
        entry.groupItemId = groupId
        add(entry: entry, itemId: itemId)
        return entry.id
    }

    /// Whether the existing item `itemId` can become the group value of an entry. It must be an
    /// ordinary, visible item that is no group and has no groups itself — the same predicate
    /// `canMoveIntoGroup` applies — and, when the hosting item is known, not the host itself.
    /// A host is never a group (`canHostGroupValues`), so no cycle can form. See CODE_AUDIT §5.17.
    @MainActor func canBecomeGroup(itemId: UUID, in hostItemId: UUID?) -> Bool {
        guard let item = itemControllable.itemSync(for: itemId) as? Model,
              isMovableIntoGroup(item) else { return false }
        guard let hostItemId else { return true }
        guard hostItemId != itemId,
              let host = itemControllable.itemSync(for: hostItemId) as? Model else { return false }
        return canHostGroupValues(host)
    }

    @MainActor func convertToGroup(itemId: UUID, entryId: UUID, existingItemId: UUID?) async -> UUID {
        guard let item = editModel(for: itemId), let index = item.entries.firstIndex(where: { $0.id == entryId }) else { return UUID() }

        let groupId: UUID
        if let existingItemId, editModel(for: existingItemId) != nil {
            // The same rules as the candidate list, so a stale or crafted request cannot turn an
            // item into a group of itself or of its own group. See CODE_AUDIT §5.17.
            guard canBecomeGroup(itemId: existingItemId, in: itemId) else { return UUID() }
            // A hidden group has no folder, as in `moveIntoGroup`; the folder would keep listing
            // it. See CODE_AUDIT_26 §5.73.
            if editModel(for: existingItemId)?.parentId != nil {
                removeItemFromParent(itemId: existingItemId, oneUp: false, moveFiles: false)
            }
            guard var existingGroup = editModel(for: existingItemId) else { return UUID() }
            groupId = existingItemId
            existingGroup.groupId = itemId
            existingGroup.isGroupHiddenToggle = true
            save(updated: existingGroup, message: String(localized: "prepare group", bundle: .module))
            item.entries[index].name = existingGroup.name
            item.entries[index].content = existingGroup.description
        } else {
            groupId = await itemControllable.addNew(type: .item)
            reset(hidden: true, itemId: groupId)
            guard var group = editModel(for: groupId) else { return groupId }
            group.name = item.entries[index].name.withoutLink()
            group.description = item.entries[index].content
            group.groupId = itemId
            save(updated: group, message: String(localized: "prepare group", bundle: .module))
        }
        item.entries[index].groupItemId = groupId
        save(updated: item, message: String(localized: "Convert to group", bundle: .module))
        return groupId
    }

    /// An item can move into another when it is an ordinary, visible item that is not a group
    /// itself and owns no group values (nested groups are not supported), and the target is an
    /// ordinary, visible item that is not a group either.
    @MainActor func canMoveIntoGroup(itemId: UUID, into targetId: UUID) -> Bool {
        guard itemId != targetId,
              let item = itemControllable.itemSync(for: itemId) as? Model,
              let target = itemControllable.itemSync(for: targetId) as? Model else { return false }
        return isMovableIntoGroup(item) && canHostGroupValues(target)
    }

    /// Turns the existing item `itemId` into a hidden group value of `targetId`: the new entry's
    /// group link is the item's id, the item gets `groupId = targetId` and is hidden. The item
    /// keeps its id, so every link to it stays valid.
    @MainActor func moveIntoGroup(itemId: UUID, into targetId: UUID) -> UUID? {
        guard canMoveIntoGroup(itemId: itemId, into: targetId), let item = editModel(for: itemId) else { return nil }

        // A hidden group has no folder; the folder would keep listing it.
        if item.parentId != nil {
            removeItemFromParent(itemId: itemId, oneUp: false, moveFiles: false)
        }
        guard var group = editModel(for: itemId) else { return nil }
        group.groupId = targetId
        group.isGroupHiddenToggle = true
        save(updated: group, message: String(localized: "prepare group", bundle: .module))

        // The entry mirrors the item's name and description, as `convertToGroup` does: editing
        // the entry writes both back to the item.
        var entry = Model.Entry.empty
        entry.name = group.name
        entry.content = group.description
        entry.groupItemId = itemId
        add(entry: entry, itemId: targetId)
        return entry.id
    }

    @MainActor private func isMovableIntoGroup(_ item: Model) -> Bool {
        guard canHostGroupValues(item) else { return false }
        return !item.entries.contains { $0.groupItemId != nil }
    }

    @MainActor private func canHostGroupValues(_ item: Model) -> Bool {
        !item.specialCategory
            && item.groupId == nil
            && item.displayState == DisplayStateMask.fullVisible.rawValue
    }

    @MainActor func groupFolders(itemId: UUID, sourceEntryId: UUID) -> [FolderRepresentable] {
        guard let item = itemControllable.itemSync(for: itemId) as? Model else { return [] }
        return item.entries.compactMap {
            guard $0.id != sourceEntryId, let groupItemId = $0.groupItemId else { return nil }
            return FolderRepresentable(id: groupItemId, name: $0.name)
        }
    }

    @MainActor func parentFolder(itemId: UUID) -> FolderRepresentable? {
        guard let item = itemControllable.itemSync(for: itemId) as? Model else { return nil }
        let resolvedParentId = item.groupId ?? item.parentId
        guard let resolvedParentId, let parent = itemControllable.itemSync(for: resolvedParentId) as? Model else { return nil }
        return FolderRepresentable(id: parent.id, name: parent.name)
    }
}

public extension EditControllable where Model: GroupableModel, Model.Entry: GroupableEntry {
    /// Deleting an item deletes the groups its entries stand for; a folder's entries are its
    /// members, which are not deleted with it here.
    @MainActor func willDeleteChildren(of item: Model) async {
        guard item.category != .folder else { return }
        for entry in item.entries {
            guard let groupItemId = entry.groupItemId else { continue }
            await Task.yield()
            await delete(itemId: groupItemId)
        }
    }
}
