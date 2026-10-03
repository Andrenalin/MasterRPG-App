// @copyright André Trettin

import CoreRPG
import Foundation

// MARK: - Duplication
// Split out of EditController.swift — see CODE_AUDIT_Character §9.7.

extension EditController {
    @MainActor public func duplicate(item: any ItemDataAccessible) async {
        let originalParentId = itemController.itemSync(for: item.id, noGame: true)?.parentId
        let copyId = await duplicate(itemId: item.id, withCopy: true)
        let folderMessage = String(localized: "Duplicate folder", bundle: .module).localizedString

        // For folders: rebuild entries with independent child copies (duplicate() produces
        // stale entry IDs), recursing into any child that is itself a folder so nested
        // folder structures get independent copies all the way down, instead of only the
        // outermost level. See CODE_AUDIT_EditItem §5.4.
        // Library-scoped: a duplicate is persisted also during a running game.
        // See CODE_AUDIT_Folder §5.21.
        if item.isFolder, let copyFolder = folderEditModel(for: copyId, scope: .library) {
            copyFolder.entries = await duplicateFolderEntries(of: item.id, newParentId: copyId)
            saveFolderEdit(copyFolder, message: folderMessage, scope: .library)
        }

        // For collections: ValueModel.duplicate() creates new entry IDs (childId = id), losing the
        // member references. Replace the broken entries in one shot with correct newChild entries.
        if !item.isFolder, item.category.isCollection,
           let originalCollection = folderEditModel(for: item.id, scope: .library),
           let copyCollection = folderEditModel(for: copyId, scope: .library) {
            copyCollection.entries = originalCollection.entries.map { Model.Entry.newChild(id: $0.childId) }
            saveFolderEdit(copyCollection, message: String(localized: "Fix collection entries", bundle: .module).localizedString, scope: .library)
        }

        // Re-register the duplicate in the same parent folder
        if let parentId = originalParentId {
            addItem(itemId: copyId, parentId: parentId)
        }

        // Add the duplicate as a new reference in every collection that contains the original.
        // Skip when duplicating a collection itself (collections cannot be members of other collections).
        // A collection only references its members, so this does not change the copy's
        // visibility; `addGroup` hid it. See CODE_AUDIT_Folder §5.16.
        if !item.specialCategory {
            let originalId = item.id
            for containerId in itemControllable.itemDataModel.items {
                guard let container = itemControllable.itemSync(for: containerId, noGame: true),
                      container.category.isCollection,
                      container.entries.contains(where: { $0.childId == originalId }) else { continue }
                addItem(itemId: copyId, parentId: containerId)
            }
        }
    }

    /// Recursively duplicates every folder-membership child of `originalFolderId`,
    /// reparenting each copy under `newParentId`, and recursing into any child that is
    /// itself a folder. See CODE_AUDIT_EditItem §5.4.
    ///
    /// `visited` guards against a cycle in the folder-membership graph (a
    /// plausible outcome of a merge/import bug, or two devices concurrently
    /// editing folder membership via CloudKit sync) recursing indefinitely
    /// and crashing with a stack overflow; `RecursionLimits.maxValueLinkDepth`
    /// bounds legitimately-deep-but-acyclic nesting the same way the
    /// sibling walk in `gameValueEntryUpdate` does. See CODE_AUDIT_13 §5.2.
    @MainActor private func duplicateFolderEntries(of originalFolderId: UUID, newParentId: UUID, visited: Set<UUID> = []) async -> [Model.Entry] {
        guard !visited.contains(originalFolderId), visited.count < RecursionLimits.maxValueLinkDepth,
              let originalFolder = folderEditModel(for: originalFolderId, scope: .library) else { return [] }
        let visited = visited.union([originalFolderId])
        var newEntries: [Model.Entry] = []
        for entry in originalFolder.entries {
            // Only children that still belong to the folder; a stale entry can point at an item
            // that lives elsewhere. See CODE_AUDIT_Folder §5.1.
            guard itemController.itemSync(for: entry.childId, noGame: true)?.parentId == originalFolderId else { continue }
            let childCopyId = await duplicate(itemId: entry.childId, withCopy: false)
            if let childCopy = folderEditModel(for: childCopyId, scope: .library) {
                childCopy.parentId = newParentId
                if let originalChild = itemController.itemSync(for: entry.childId, noGame: true), originalChild.isFolder {
                    childCopy.entries = await duplicateFolderEntries(of: entry.childId, newParentId: childCopyId, visited: visited)
                }
                saveFolderEdit(childCopy, message: String(localized: "Duplicate child", bundle: .module).localizedString, scope: .library)
            }
            newEntries.append(Model.Entry.newChild(id: childCopyId))
        }
        return newEntries
    }

    @MainActor func duplicate(itemId: UUID, withCopy: Bool) async -> UUID {
        let (duplicates, copyId, mapper) = duplicateSubValue(id: itemId, withCopy: withCopy)
        root.linkController.repairDuplicateLinks(models: duplicates, mapper: mapper)
        for duplicate in duplicates {
            // Plain `replace(model:isInsert:)` does not touch the link register — only
            // `replaceImportedModel` and the normal `EditControllable.saveChanges` edit path
            // do. A duplicated item's links were being repaired but never registered, so
            // backlink/orphan-detection bookkeeping silently drifted for every duplicate.
            // See CODE_AUDIT.md §9.4 / CODE_AUDIT_Character §9.16.
            // Persisted also during a running game. See CODE_AUDIT_Folder §5.21.
            itemController.replaceImportedModel(model: duplicate, isInsert: true, forceSave: true)
        }
        return copyId
    }

    /// `visited` guards against a cycle in the item/value graph recursing
    /// indefinitely and crashing with a stack overflow; `RecursionLimits.maxValueLinkDepth`
    /// bounds legitimately-deep-but-acyclic nesting. See CODE_AUDIT_13 §5.2.
    @MainActor
    private func duplicateSubValue(id: UUID, withCopy: Bool, visited: Set<UUID> = []) -> ([ValueModel], UUID, [UUID: UUID]) {
        guard !visited.contains(id), visited.count < RecursionLimits.maxValueLinkDepth,
              let item = itemController.itemSync(for: id) else { return ([], id, [:]) }
        let visited = visited.union([id])

        var duplicates: [ValueModel] = []
        let copyItem: ValueModel = withCopy ? item.duplicate() : item.duplicateWithoutCopy()
        duplicates.append(copyItem)

        var mapper: [UUID: UUID] = [id: copyItem.id]
        let subValueIds = item.duplicateSubValueIds()
        subValueIds.forEach {
            let (newDuplicates, newCopyId, newMapper) = duplicateSubValue(id: $0, withCopy: false, visited: visited)
            mapper[$0] = newCopyId
            mapper.merge(newMapper) { first, _ in return first }
            duplicates.append(contentsOf: newDuplicates)
        }
        for (index, entry) in copyItem.entries.enumerated() {
            guard let valueId = entry.valueId else { continue }
            if let copyId = mapper[valueId] {
                copyItem.entries[index].valueId = copyId
                duplicates.first(where: { $0.id == copyId })?.groupId = copyItem.id
            }
        }
        return (duplicates, copyItem.id, mapper)
    }
}
