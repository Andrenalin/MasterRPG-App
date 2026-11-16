// @copyright André Trettin

import SwiftUI
import os.log

// MARK: - Folder / Collection

/// Where a folder or collection membership edit reads and writes.
public enum FolderEditScope: Sendable {
    /// The permanent library copy, persisted also during a running game. Edits from the library
    /// UI use this: a plain `save` lands in game memory only during a game and is lost at game
    /// end, while the file moves it triggers are real. See CODE_AUDIT_Folder §5.21.
    case library
    /// Whatever `editModel(for:)`/`save(updated:message:)` use now — the import repair, which
    /// runs on game deliveries too.
    case current
}

public extension EditControllable {
    @MainActor func addItem(itemId: UUID, parentId: UUID?) {
        addItem(itemId: itemId, parentId: parentId, scope: .library)
    }

    @MainActor func remove(itemId: UUID, parentId: UUID, oneUp: Bool) {
        guard let parentItem = folderEditModel(for: parentId, scope: .library) else { return }
        if parentItem.isFolder, itemControllable.itemSync(for: itemId, noGame: true)?.parentId == parentId {
            removeItemFromParent(itemId: itemId, oneUp: oneUp, scope: .library)
        } else {
            // A collection, or a folder whose entry for this item is stale (the item lives in
            // another folder or at root): only the entry is removed. Going through the item's own
            // parent here left the stale entry with no way to remove it. See CODE_AUDIT_Folder §5.30.
            parentItem.entries.removeAll(where: { $0.childId == itemId })
            saveFolderEdit(parentItem, message: String(localized: "Removed item", bundle: .module).localizedLowercase.localizedString, scope: .library)
        }
    }

    @MainActor func removeItemFromParent(itemId: UUID, oneUp: Bool, moveFiles: Bool = true) {
        removeItemFromParent(itemId: itemId, oneUp: oneUp, moveFiles: moveFiles, scope: .current)
    }

    @MainActor func cleanFolder(itemId: UUID) {
        guard let item = editModel(for: itemId) else { return }
        item.entries.removeAll {
            guard let child = itemControllable.itemSync(for: $0.childId) else { return true }
            if child.parentId != itemId {
                return true
            }
            return false
        }
        // A member listed by two entries (see `FolderEntryMerge.deduplicated`) is repaired here
        // too, so "Validate & Repair" writes the fix and its final save sends it to other devices.
        if let unique = FolderEntryMerge.deduplicated(item.entries, id: \.id, childId: \.childId) {
            item.entries = unique
        }
        save(updated: item, message: String(localized: "update folder", bundle: .module))
    }
}

extension EditControllable {
    @MainActor func addItem(itemId: UUID, parentId: UUID?, scope: FolderEditScope) {
        guard let parentId, itemId != parentId,
              let parentItem = folderEditModel(for: parentId, scope: scope),
              var item = folderEditModel(for: itemId, scope: scope) else { return }
        // Refuse a link that would make `itemId` an ancestor of itself: if `parentId` is
        // already reachable by descending from `itemId` through folder/collection membership,
        // linking `itemId` under `parentId` below would close the loop. Every recursive
        // search/list tree-builder (`buildFolderTreeNode`, `appendToFlat`, …) walks this exact
        // `entries`/`childId` graph assuming it's acyclic and has no cycle guard of its own.
        guard !isDescendant(parentId, of: itemId) else { return }
        if parentItem.isFolder && item.parentId != nil {
            removeItemFromParent(itemId: itemId, oneUp: false, moveFiles: false, scope: scope)
            guard let refreshed = folderEditModel(for: itemId, scope: scope) else { return }
            item = refreshed
        }

        if item.isFolder && (parentItem.specialCategory && !parentItem.isFolder) {
            return
        }

        var entries = parentItem.entries
        if parentItem.category != .item {
            let entry = Model.Entry.newChild(id: itemId)
            if parentItem.category == .folder {
                entries.removeAll { $0.childId == itemId }
            }
            // A collection only references its members and may list one several times.
            entries.append(entry)
            if parentItem.category == .folder {
                // Names are looked up once per entry, not twice per comparison (§7.27).
                entries = entries
                    .map { (name: itemControllable.nameSync(itemId: $0.childId), entry: $0) }
                    .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                    .map(\.entry)
            }
        }

        var shouldCheckForMove: Bool = false
        if parentItem.category == .folder || parentItem.category == .item {
            item.parentId <=> parentItem.id
            if parentItem.category == .item {
                item.displayState <=> 1
            }
            saveFolderEdit(item, message: String(localized: "Added parent", bundle: .module), scope: scope)
            shouldCheckForMove = true
        }

        if parentItem.category != .item {
            parentItem.entries <=> entries
        }
        saveFolderEdit(parentItem, message: String(localized: "Added item", bundle: .module), scope: scope)

        if shouldCheckForMove {
            movedFileTree(itemId: itemId)
        }
    }

    @MainActor func removeItemFromParent(itemId: UUID, oneUp: Bool, moveFiles: Bool = true, scope: FolderEditScope) {
        guard var item = folderEditModel(for: itemId, scope: scope), let parentId = item.parentId else { return }
        item.parentId = nil
        saveFolderEdit(item, message: String(localized: "Removed parent", bundle: .module).localizedLowercase.localizedString, scope: scope)

        guard let parentItem = folderEditModel(for: parentId, scope: scope) else { return }
        var entries = parentItem.entries
        entries.removeAll(where: { $0.childId == itemId })
        parentItem.entries = entries
        saveFolderEdit(parentItem, message: String(localized: "Removed item", bundle: .module).localizedLowercase.localizedString, scope: scope)

        guard oneUp && parentItem.parentId != nil else {
            if moveFiles {
                movedFileTree(itemId: itemId)
            }
            return
        }
        addItem(itemId: itemId, parentId: parentItem.parentId, scope: scope)
    }

    /// Returns true if `candidateId` is reachable from `rootId` by descending through folder/
    /// collection membership (`entries.childId`) — i.e. whether `rootId` is already an
    /// ancestor of `candidateId` in that graph. `visited` makes the walk itself cycle-safe in
    /// case one already exists somehow, rather than relying on the graph being acyclic.
    @MainActor private func isDescendant(_ candidateId: UUID, of rootId: UUID) -> Bool {
        var visited: Set<UUID> = []
        var stack: [UUID] = [rootId]
        while let current = stack.popLast() {
            guard visited.insert(current).inserted else { continue }
            if current == candidateId { return true }
            guard let currentItem = itemControllable.itemSync(for: current) else { continue }
            stack.append(contentsOf: currentItem.entries.map(\.childId))
        }
        return false
    }

    @MainActor public func folderEditModel(for itemId: UUID, scope: FolderEditScope) -> Model? {
        switch scope {
        case .library:
            itemControllable.itemSync(for: itemId, noGame: true)?.copy() as? Model
        case .current:
            editModel(for: itemId)
        }
    }

    @MainActor public func saveFolderEdit(_ item: Model, message: String, scope: FolderEditScope) {
        switch scope {
        case .current:
            save(updated: item, message: message)
        case .library:
            validateBeforeSave(model: item)
            guard !itemControllable.libraryModel(id: item.id, matches: item) else { return }
            if let stored = itemControllable.itemSync(for: item.id, noGame: true) {
                let previous = stored.copy()
                editorModel.markLibraryScopedUndo(previous)
                editorModel.undoManaged.previousValue(previous, title: message)
            }
            itemControllable.persistMembershipChange(model: item)
        }
    }

    /// Moves the files of `itemId` and, for a folder, of everything below it, to match their
    /// folder path. Moving a folder used to leave its descendants' files at the old path.
    /// See CODE_AUDIT_Folder §5.30.
    @MainActor func movedFileTree(itemId: UUID) {
        var visited: Set<UUID> = []
        var stack = [itemId]
        while let current = stack.popLast(), visited.count < FolderTreeDepthLimit.max * FolderTreeDepthLimit.max {
            guard visited.insert(current).inserted,
                  let item = itemControllable.itemSync(for: current, noGame: true) else { continue }
            movedFile(itemId: current)
            if item.isFolder {
                stack.append(contentsOf: item.entries.map(\.childId).filter {
                    itemControllable.itemSync(for: $0, noGame: true)?.parentId == current
                })
            }
        }
    }
}
