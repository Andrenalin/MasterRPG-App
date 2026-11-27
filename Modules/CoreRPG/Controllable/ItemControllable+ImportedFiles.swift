// @copyright André Trettin

import Foundation
import Observation
import os.log

// The imported-file and library-file helpers, split out of ItemControllable.swift. See CODE_AUDIT_29 §9.9.

public extension ItemControllable {
    /// The file references of every permanent-library item, except `excludedId`.
    @MainActor func libraryFileUrls(excluding excludedId: UUID? = nil) -> [FileUrl] {
        itemDataModel.items.compactMap { itemId in
            guard itemId != excludedId else { return nil }
            return itemSync(for: itemId, noGame: true)?.fileUrl
        }
    }

    /// Whether another permanent-library item references the stored file of `fileUrl`. Such a
    /// file must outlive the delete or the file replacement of one of its items.
    /// See CODE_AUDIT_21 §5.2.
    @MainActor func isFileUsedElsewhere(_ fileUrl: FileUrl, excluding itemId: UUID) -> Bool {
        // A cached remote file is named after its file id, so it is never shared.
        guard let controller = fileUrlDataController, fileUrl.location != .url else { return false }
        // The cheap name comparison first: resolving a stored location touches the file system.
        let name = fileUrl.rawUrl.lastPathComponent
        return libraryFileUrls(excluding: itemId).contains {
            $0.rawUrl.lastPathComponent == name && controller.isSameStoredFile($0, fileUrl)
        }
    }

    /// After an import applied `itemId`, keeps whichever of the file it wrote and the item's
    /// previous file the library item references now, and removes the other one unless another
    /// item uses it. Imports used to leave the superseded file (or an unused new one) behind.
    /// See CODE_AUDIT_Folder §5.26.
    @MainActor internal func settleImportedFile(_ file: ImportedFileWrite, itemId: UUID) async {
        guard let controller = fileUrlDataController else { return }
        let current = itemSync(for: itemId, noGame: true)?.fileUrl
        let others = libraryFileUrls(excluding: itemId)
        func isUsedElsewhere(_ fileUrl: FileUrl) -> Bool {
            others.contains { controller.isSameStoredFile($0, fileUrl) }
        }
        if let current, controller.isSameStoredFile(current, file.written) {
            if let previous = file.previous, !controller.isSameStoredFile(previous, file.written), !isUsedElsewhere(previous) {
                await controller.deleteReplaced(previous, keeping: file.written)
            }
        } else if !isUsedElsewhere(file.written) {
            await controller.removeStoredFile(file.written)
        }
    }

    /// Merge keeps the local display state and folder placement, so an item in the local trash
    /// stayed there after re-importing a backup that has it, and was purged at the next launch.
    /// A visible imported copy restores it, with the backup's folder placement. Returns `merged`
    /// unchanged when there is nothing to restore. See CODE_AUDIT_Folder §5.20.
    @MainActor func restoringTrashedItem(merged: ModelType?, imported: ModelType) -> ModelType? {
        let trashed = DisplayStateMask.totalHidden.rawValue
        guard let imported = imported as? Model, imported.displayState != trashed,
              let local = itemSync(for: imported.id, noGame: true), local.displayState == trashed else { return merged }
        var restored = ((merged as? Model) ?? local).copy()
        restored.displayState = imported.displayState
        restored.parentId = imported.parentId
        return restored
    }

    /// An imported folder may be a partial copy: a subset export lists only the exported
    /// children. Overwriting the local folder with it dropped its other children, which then
    /// vanished from the folder list. The local children that still belong to the folder are
    /// kept. See CODE_AUDIT_Folder §5.8.
    @MainActor func keepingLocalFolderChildren(_ model: ModelType) -> ModelType {
        guard let imported = model as? Model, imported.isFolder,
              let local = itemSync(for: imported.id, noGame: true) else { return model }
        let localChildren = local.entries.filter { itemSync(for: $0.childId, noGame: true)?.parentId == local.id }
        guard !localChildren.isEmpty else { return model }
        let result = imported.copy()
        result.entries = FolderEntryMerge.merged(local: imported.entries, remote: localChildren, id: \.id, name: \.name, childId: \.childId)
        return result
    }

    /// Whether the permanent-library copy of `id` still equals `snapshot`; both absent counts as
    /// equal. Lets a caller that suspended after taking `snapshot` detect a write that landed in
    /// between. See CODE_AUDIT_Folder §3.6, §3.17.
    @MainActor func libraryModel(id: UUID, matches snapshot: (any ModelType)?) -> Bool {
        let current = itemSync(for: id, noGame: true)
        switch (current, snapshot) {
        case (nil, nil):
            return true
        case let (current?, snapshot?):
            guard let snapshot = snapshot as? Model else { return false }
            return current == snapshot
        default:
            return false
        }
    }

    /// Persists `fileUrl` on the permanent-library copy of `itemId` and mirrors only that field
    /// into a loaded game-memory copy. A whole-model `replace` would either be skipped (when
    /// handed the stored instance) or overwrite the game copy's session-only changes with the
    /// library state. See CODE_AUDIT_Folder §3.11.
    @MainActor func persistFileUrl(_ fileUrl: FileUrl, itemId: UUID) {
        if let library = itemSync(for: itemId, noGame: true), library.fileUrl != fileUrl {
            var updated = library.copy()
            updated.fileUrl = fileUrl
            if library.replace(with: updated) {
                itemDataModel.markIndexDirty(library.id)
                do {
                    try dataControllable?.replaceSync(id: library.id, with: library.copy())
                } catch {
                    recordPersistenceFailure(error, operation: "ItemControllable.persistFileUrl")
                }
            }
        }
        if var gameItem = itemDataModel.gameItemData[itemId] as? Model, gameItem.fileUrl != fileUrl {
            gameItem.fileUrl = fileUrl
        }
    }
}
