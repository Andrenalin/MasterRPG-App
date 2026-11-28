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
    /// The group is created with the caller's write policy, then filled and linked in one undo
    /// step. See CODE_AUDIT_Edit_Save §5.5, §5.9.
    @MainActor func addNewGroup(itemId: UUID, forceSave: Bool) async -> UUID {
        let groupId = await itemControllable.addNew(type: .item, forceSave: forceSave)
        return attachAsGroup(itemId: itemId, groupId: groupId, forceSave: forceSave)
    }

    /// Makes the existing item `groupId` the hidden group of a new entry of `itemId`, in one undo
    /// step. Returns the new entry's id (`groupId` when the group item is gone). The one rule
    /// behind `addNewGroup` and Character's `addItemAsGroup`, which kept a copy of it.
    /// See CODE_AUDIT_Edit_Save §9.4.
    @MainActor func attachAsGroup(itemId: UUID, groupId: UUID, forceSave: Bool) -> UUID {
        asOneUndoStep(String(localized: "prepare group", bundle: .module)) {
            reset(hidden: true, itemId: groupId, forceSave: forceSave)
            guard var group = editModel(for: groupId) else { return groupId }
            group.groupId = itemId
            save(updated: group, message: String(localized: "prepare group", bundle: .module), forceSave: forceSave)
            var entry = Model.Entry.empty
            entry.name = group.name
            entry.groupItemId = groupId
            add(entry: entry, itemId: itemId, forceSave: forceSave)
            return entry.id
        }
    }

    /// Writes a group entry's edit to its group item: the name without the link the sheet shows
    /// it as, and the content as the description, in one save. `false` when the entry is no
    /// group entry. Adventure and Character each wrote this with two saves.
    /// See CODE_AUDIT_Edit_Save §9.4, §7.1.
    @discardableResult
    @MainActor func updateGroupItem(itemId: UUID, entryId: UUID, name: String, content: String, forceSave: Bool) -> Bool {
        guard let groupId = editModel(for: itemId)?.entries.first(where: { $0.id == entryId })?.groupItemId else { return false }
        reset(name: name.withoutLink(), description: content, tags: nil, itemId: groupId, forceSave: forceSave)
        return true
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

    /// The new group is created first; the host and its entry are read after that await, so an
    /// edit made while the group was created is kept instead of being overwritten with a stale
    /// copy. The rest is one undo step, and a folder the existing item leaves follows the write
    /// policy (memory-only during a game unless forced). See CODE_AUDIT_Edit_Save §3.2, §5.5, §5.8.
    @MainActor func convertToGroup(itemId: UUID, entryId: UUID, existingItemId: UUID?, forceSave: Bool) async -> UUID {
        guard editModel(for: itemId)?.entries.contains(where: { $0.id == entryId }) == true else { return UUID() }
        let existingGroupId = existingItemId.flatMap { editModel(for: $0) != nil ? $0 : nil }
        // The same rules as the candidate list, so a stale or crafted request cannot turn an
        // item into a group of itself or of its own group. See CODE_AUDIT §5.17.
        if let existingGroupId, !canBecomeGroup(itemId: existingGroupId, in: itemId) { return UUID() }
        let newGroupId: UUID? = existingGroupId == nil ? await itemControllable.addNew(type: .item, forceSave: forceSave) : nil

        return asOneUndoStep(String(localized: "Convert to group", bundle: .module)) {
            guard let item = editModel(for: itemId), let index = item.entries.firstIndex(where: { $0.id == entryId }) else {
                return newGroupId ?? UUID()
            }
            let groupId: UUID
            if let existingGroupId {
                // A hidden group has no folder, as in `moveIntoGroup`; the folder would keep
                // listing it. See CODE_AUDIT_26 §5.73.
                if editModel(for: existingGroupId)?.parentId != nil {
                    removeItemFromParent(itemId: existingGroupId, oneUp: false, moveFiles: false, forceSave: forceSave)
                }
                guard var existingGroup = editModel(for: existingGroupId) else { return UUID() }
                groupId = existingGroupId
                existingGroup.groupId = itemId
                existingGroup.isGroupHiddenToggle = true
                save(updated: existingGroup, message: String(localized: "prepare group", bundle: .module), forceSave: forceSave)
                item.entries[index].name = existingGroup.name
                item.entries[index].content = existingGroup.description
            } else if let newGroupId {
                groupId = newGroupId
                reset(hidden: true, itemId: groupId, forceSave: forceSave)
                guard var group = editModel(for: groupId) else { return groupId }
                group.name = item.entries[index].name.withoutLink()
                group.description = item.entries[index].content
                group.groupId = itemId
                save(updated: group, message: String(localized: "prepare group", bundle: .module), forceSave: forceSave)
            } else {
                return UUID()
            }
            item.entries[index].groupItemId = groupId
            save(updated: item, message: String(localized: "Convert to group", bundle: .module), forceSave: forceSave)
            return groupId
        }
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
    @MainActor func moveIntoGroup(itemId: UUID, into targetId: UUID, forceSave: Bool) -> UUID? {
        guard canMoveIntoGroup(itemId: itemId, into: targetId), let item = editModel(for: itemId) else { return nil }

        return asOneUndoStep(String(localized: "prepare group", bundle: .module)) {
            // A hidden group has no folder; the folder would keep listing it. With the write
            // policy: unforced, the folder change stays in game memory. See CODE_AUDIT_Edit_Save §5.8.
            if item.parentId != nil {
                removeItemFromParent(itemId: itemId, oneUp: false, moveFiles: false, forceSave: forceSave)
            }
            guard var group = editModel(for: itemId) else { return nil }
            group.groupId = targetId
            group.isGroupHiddenToggle = true
            save(updated: group, message: String(localized: "prepare group", bundle: .module), forceSave: forceSave)

            // The entry mirrors the item's name and description, as `convertToGroup` does:
            // editing the entry writes both back to the item.
            var entry = Model.Entry.empty
            entry.name = group.name
            entry.content = group.description
            entry.groupItemId = itemId
            add(entry: entry, itemId: targetId, forceSave: forceSave)
            return entry.id
        }
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

    @MainActor func groupItemIds(of item: any ItemDataAccessible) -> Set<UUID> {
        guard let item = item as? Model, item.category != .folder else { return [] }
        return Set(item.entries.compactMap(\.groupItemId))
    }

    /// An import that turned a group entry into a plain one left the group item behind: hidden,
    /// owned by the item and shown nowhere. Only a group that still names `owner` as its `groupId`
    /// goes; `delete` takes the groups nested in it along.
    @MainActor func removeStaleGroups(_ groupOwners: [UUID: UUID]) async {
        for (groupItemId, ownerId) in groupOwners {
            guard let group = itemControllable.itemSync(for: groupItemId, noGame: true) as? Model,
                  group.groupId == ownerId else { continue }
            // The owner may have gained the group again by a later item of the same import.
            if let owner = itemControllable.itemSync(for: ownerId, noGame: true) as? Model,
               groupItemIds(of: owner).contains(groupItemId) { continue }
            await delete(itemId: groupItemId)
        }
    }
}
