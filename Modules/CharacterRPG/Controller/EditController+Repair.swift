// @copyright André Trettin

import CoreRPG
import Foundation
import os.log

// MARK: - Final Repair
// Split out of EditController.swift — see CODE_AUDIT_Character §9.7.

extension EditController {
    @MainActor func repairCharacterConstraints() {
        let itemIds = itemControllable.itemDataModel.items

        // Build: groupItemId → [ownerIds that reference it via entry.valueId]
        // editModel returns ValueModel, giving typed access to ValueEntryModel.valueId
        var valueIdOwners: [UUID: [UUID]] = [:]
        for itemId in itemIds {
            guard let item = editModel(for: itemId), !item.isHidden else { continue }
            for entry in item.entries {
                guard let valueId = entry.valueId else { continue }
                valueIdOwners[valueId, default: []].append(itemId)
            }
        }

        for itemId in itemIds {
            guard let item = itemControllable.itemSync(for: itemId) as? ValueModel,
                  !item.isHidden else { continue }

            if item.isFolder && item.groupId == nil {
                repairFolderConstraints(itemId: itemId)
            } else if item.category == itemControllable.collectionCategory && item.displayState == DisplayStateMask.fullVisible.rawValue && item.groupId == nil {
                repairCollectionConstraints(itemId: itemId)
            } else if item.displayState == DisplayStateMask.groupHidden.rawValue {
                repairGroupItemConstraints(itemId: itemId, valueIdOwners: valueIdOwners)
            } else if item.displayState == DisplayStateMask.fullVisible.rawValue && item.groupId == nil && !item.specialCategory {
                repairCharacterItemConstraints(itemId: itemId)
            }
        }
    }

    @MainActor private func repairFolderConstraints(itemId: UUID) {
        guard let item = editModel(for: itemId) else { return }
        let before = item.entries.map(\.childId)

        let removedNames = before.compactMap { childId -> String? in
            guard let child = itemControllable.itemSync(for: childId) else { return nil }
            let badParent = child.parentId != itemId
            let isNestedFolder = child.isFolder
            let isHidden = child.displayState != DisplayStateMask.fullVisible.rawValue
            guard badParent || isNestedFolder || isHidden else { return nil }
            return child.name
        }

        item.entries = item.entries.filter { entry in
            guard let child = itemControllable.itemSync(for: entry.childId),
                  child.displayState == DisplayStateMask.fullVisible.rawValue,
                  child.parentId == itemId,
                  !child.isFolder
            else { return false }
            return true
        }
        item.entries.sort {
            let n1 = itemControllable.nameSync(itemId: $0.childId)
            let n2 = itemControllable.nameSync(itemId: $1.childId)
            return n1.localizedCompare(n2) == .orderedAscending
        }
        guard item.entries.map(\.childId) != before else { return }

        let afterNames = item.entries.map { itemControllable.nameSync(itemId: $0.childId) }
        if !removedNames.isEmpty {
            Logger.editController.warning("[Repair] Folder '\(item.name, privacy: .private)': removed invalid children \(removedNames, privacy: .private)")
        }
        Logger.editController.info("[Repair] Folder '\(item.name, privacy: .private)': entries now \(afterNames, privacy: .private)")

        save(updated: item, message: String(localized: "Repair folder", bundle: .module).localizedString)
    }

    @MainActor private func repairCollectionConstraints(itemId: UUID) {
        guard let item = editModel(for: itemId) else { return }
        let before = item.entries.count

        let removedNames: [String] = item.entries.compactMap { entry in
            guard let child = itemControllable.itemSync(for: entry.childId) as? ValueModel else {
                return "<missing \(entry.childId)>"
            }
            let invalid = child.displayState != DisplayStateMask.fullVisible.rawValue || child.groupId != nil || child.specialCategory
            return invalid ? child.name : nil
        }

        item.entries = item.entries.filter { entry in
            guard let child = itemControllable.itemSync(for: entry.childId) as? ValueModel,
                  child.displayState == DisplayStateMask.fullVisible.rawValue,
                  child.groupId == nil,
                  !child.specialCategory
            else { return false }
            return true
        }
        guard item.entries.count != before else { return }

        Logger.editController.warning("[Repair] Collection '\(item.name, privacy: .private)': removed \(before - item.entries.count) invalid children \(removedNames, privacy: .private)")

        save(updated: item, message: String(localized: "Repair collection", bundle: .module).localizedString)
    }

    @MainActor private func repairCharacterItemConstraints(itemId: UUID) {
        guard let item = editModel(for: itemId) else { return }
        var changed = false

        // Repair 1: orphaned parentId — item not present in the folder's entries
        if let parentId = item.parentId {
            let isInFolder = itemControllable.itemSync(for: parentId).map { parent in
                !parent.isHidden && parent.isFolder && parent.entries.contains { $0.childId == itemId }
            } ?? false
            if !isInFolder {
                let parentName = itemControllable.nameSync(itemId: parentId)
                Logger.editController.warning("[Repair] Character '\(item.name, privacy: .private)': cleared orphaned parentId (folder '\(parentName, privacy: .private)' has no matching entry)")
                item.parentId = nil
                changed = true
            }
        }

        // Repair 2: entry.valueId must only point to GroupItems (displayState == DisplayStateMask.groupHidden.rawValue)
        var entriesChanged = false
        let cleanedEntries: [ValueEntryModel] = item.entries.map { entry in
            guard let valueId = entry.valueId else { return entry }
            guard let target = itemControllable.itemSync(for: valueId) as? ValueModel else {
                let targetName = itemControllable.nameSync(itemId: valueId)
                Logger.editController.warning("[Repair] Character '\(item.name, privacy: .private)': entry '\(entry.name, privacy: .private)' had non-GroupItem valueId pointing to '\(targetName, privacy: .private)' — cleared")
                entriesChanged = true
                return ValueEntryModel(
                    id: entry.id, name: entry.name, type: entry.type,
                    isGenerator: entry.isGenerator, value: entry.value,
                    diceId: entry.diceId, valueId: nil, displayState: entry.displayState
                )
            }
            guard target.displayState == DisplayStateMask.groupHidden.rawValue else {
                if target.groupId == itemId, let groupItem = editModel(for: valueId) {
                    groupItem.parentId = nil
                    groupItem.displayState = DisplayStateMask.groupHidden.rawValue
                    save(updated: groupItem, message: String(localized: "Repair group item", bundle: .module).localizedString)
                    return entry
                }

                let targetName = itemControllable.nameSync(itemId: valueId)
                Logger.editController.warning("[Repair] Character '\(item.name, privacy: .private)': entry '\(entry.name, privacy: .private)' had non-GroupItem valueId pointing to '\(targetName, privacy: .private)' — cleared")
                entriesChanged = true
                return ValueEntryModel(
                    id: entry.id, name: entry.name, type: entry.type,
                    isGenerator: entry.isGenerator, value: entry.value,
                    diceId: entry.diceId, valueId: nil, displayState: entry.displayState
                )
            }
            return entry
        }
        if entriesChanged {
            item.entries = cleanedEntries
            changed = true
        }

        if changed {
            save(updated: item, message: String(localized: "Repair character item", bundle: .module).localizedString)
        }
    }

    @MainActor private func repairGroupItemConstraints(itemId: UUID, valueIdOwners: [UUID: [UUID]]) {
        guard let groupItem = editModel(for: itemId) else { return }
        let before = (groupItem.parentId, groupItem.groupId, groupItem.displayState)
        groupItem.parentId = nil // groups always on root level / no relationship to folders

        let owners = valueIdOwners[itemId]
        let firstOwnerId = owners?.first
        if groupItem.groupId != firstOwnerId {
            if let oldOwnerId = groupItem.groupId {
                removeOld(groupItemId: itemId, valueId: oldOwnerId)
            }
            groupItem.groupId = firstOwnerId
        }
        if groupItem.groupId == nil {
            // An item that no longer belongs to any group becomes a normal, visible top-level
            // item; hiding it would lose it from every list. See CODE_AUDIT_Character §9.16 and
            // CODE_AUDIT_18 §9.6.
            groupItem.displayState = DisplayStateMask.fullVisible.rawValue
        }
        // Saved only when a field changed: every save moves the CRDT clocks and syncs through
        // CloudKit. See CODE_AUDIT_23 §5.21.
        if (groupItem.parentId, groupItem.groupId, groupItem.displayState) != before {
            save(
                updated: groupItem,
                message: String(localized: "Repairing group item", bundle: .module).localizedString
            )
        }
        guard let owners, owners.count > 1 else { return }
        for ownerId in owners.dropFirst() {
            removeOld(groupItemId: itemId, valueId: ownerId)
        }
    }

    @MainActor private func removeOld(groupItemId: UUID, valueId: UUID) {
        guard let oldOwner = editModel(for: valueId) else { return }
        oldOwner.entries = oldOwner.entries.map {
            if $0.valueId == groupItemId {
                var changed = $0
                changed.valueId = nil
                return changed
            } else {
                return $0
            }
        }
        let groupItemName = itemControllable.nameSync(itemId: groupItemId)

        Logger.editController.warning("[Repair] GroupItem '\(groupItemName, privacy: .private)': removed duplicate reference from '\(oldOwner.name, privacy: .private)'")
        save(updated: oldOwner, message: String(localized: "Repair group item", bundle: .module).localizedString)
    }
}
