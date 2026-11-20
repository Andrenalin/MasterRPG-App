// @copyright André Trettin

import CoreRPG
import Foundation

// MARK: - Duplication
// Split out of EditController.swift — see CODE_AUDIT_Character §9.7.

extension EditController {
    @MainActor public func duplicate(item: any ItemDataAccessible) async {
        // Library-scoped: a duplicate is persisted also during a running game.
        // See CODE_AUDIT_Folder §5.21.
        guard let original = folderEditModel(for: item.id, scope: .library) else { return }
        let copyId = await duplicate(itemId: item.id, withCopy: true)

        // A folder's members get independent copies too, all the way down.
        // See CODE_AUDIT_EditItem §5.4, CODE_AUDIT_Folder §9.9.
        if original.isFolder {
            await duplicateFolderMembers(of: original.id, into: copyId) { member, parentId in
                let memberCopyId = await duplicate(itemId: member.id, withCopy: false)
                if let memberCopy = folderEditModel(for: memberCopyId, scope: .library) {
                    memberCopy.parentId = parentId
                    saveFolderEdit(memberCopy, message: String(localized: "Duplicate child", bundle: .module), scope: .library)
                }
                return memberCopyId
            }
        }

        // For collections: ValueModel.duplicate() creates new entry IDs (childId = id), losing the
        // member references. Replace the broken entries in one shot with correct newChild entries.
        if !original.isFolder, original.category.isCollection,
           let copyCollection = folderEditModel(for: copyId, scope: .library) {
            copyCollection.entries = original.entries.map { Model.Entry.newChild(id: $0.childId) }
            saveFolderEdit(copyCollection, message: String(localized: "Fix collection entries", bundle: .module), scope: .library)
        }

        placeDuplicate(copyId, of: original)
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

// MARK: - Generated from a photo

extension EditController {
    /// A saved Character named `name` whose portrait is the photo. "Generate" in the photo list.
    @MainActor
    func generateQuickCharacter(name: String, photoId: UUID) async -> UUID? {
        let character = ValueModel(id: UUID(), name: name, category: .item, photoId: photoId, photos: [photoId])
        itemController.replace(model: character, isInsert: true)
        return character.id
    }

    /// A copy of the Character `itemId` whose photo is replaced by `photoId`: the copy's photo
    /// list is exactly that photo. `nil` when `itemId` is gone or a folder or collection, whose
    /// copy would be a different thing than a Character with a new portrait.
    @MainActor
    func cloneCharacter(itemId: UUID, photoId: UUID) async -> UUID? {
        guard let original = folderEditModel(for: itemId, scope: .library),
              !original.specialCategory else { return nil }
        let copyId = await duplicate(itemId: itemId, withCopy: true)
        placeDuplicate(copyId, of: original)
        add(selection: [WindowItemSelection(itemId: photoId)], itemId: copyId)
        return copyId
    }
}
