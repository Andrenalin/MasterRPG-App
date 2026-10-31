// @copyright André Trettin

import Foundation

// The library side of the sync with a module's iCloud folder. See `CloudFolderScan`.

extension ItemControllable {
    /// Every item of the permanent library as far as the scan needs it, trashed items included:
    /// a trashed item still references its file until the next launch purges it.
    @MainActor func cloudScanExistingItems() -> [CloudScanExistingItem] {
        itemDataModel.items.compactMap { itemId in
            guard let item = itemSync(for: itemId, noGame: true) else { return nil }
            var fileComponents: [String]?
            if let fileUrl = item.fileUrl, fileUrl.location == .newCloud {
                fileComponents = fileUrlDataController?.cloudDocumentController.relativeComponents(of: fileUrl.rawUrl)
            }
            return CloudScanExistingItem(
                id: item.id,
                name: item.name,
                parentId: item.parentId,
                isFolder: item.isFolder,
                isTrashed: item.displayState == DisplayStateMask.totalHidden.rawValue,
                fileComponents: fileComponents,
                contentHash: item.fileUrl?.contentHash
            )
        }
    }

    /// Inserts the folders and items of `plan` into the library and returns their ids. Folders
    /// come first, so a parent exists before its children. The caller lists the new items in their
    /// folders (`EditControllable.repairFolders(itemIds:)`) and saves. `hashes` are the content
    /// hashes by `CloudFolderScan.key`, so a later rename of a new file is found as a move.
    @MainActor func insertCloudScan(_ plan: CloudScanPlan, hashes: [String: String] = [:]) -> [UUID] {
        var insertedIds: [UUID] = []
        for folder in plan.folders {
            var model = Model.empty(folder.id)
            model.name = folder.name
            model.category = .folder
            model.parentId = folder.parentId
            replace(model: model, isInsert: true, forceSave: true)
            insertedIds.append(folder.id)
        }
        for item in plan.items {
            var model = Model.empty(item.id)
            model.name = item.name
            model.category = .item
            model.parentId = item.parentId
            model.fileUrl = FileUrl(fileId: item.id, url: item.file.storedUrl, location: .newCloud, module: config.module.token, relativeUrl: nil, contentHash: hashes[CloudFolderScan.key(item.file.components)])
            replace(model: model, isInsert: true, forceSave: true)
            insertedIds.append(item.id)
        }
        return insertedIds
    }

    /// Points each moved item at its file's new path and puts it into the folder of its file, and
    /// returns the ids it changed. Only the item changes: the file is where it is, so the item
    /// does not go through `movedFile`, which would rename the file after the item. The caller
    /// lists the items in their folders (`EditControllable.repairFolders(itemIds:)`) and saves.
    @MainActor func moveCloudScanItems(_ moves: [CloudScanPlan.Move]) -> [UUID] {
        var movedIds: [UUID] = []
        for move in moves {
            guard let item = itemSync(for: move.id, noGame: true),
                  item.displayState != DisplayStateMask.totalHidden.rawValue else { continue }
            var model = item.copy()
            model.parentId = move.parentId
            if let file = move.file, let old = item.fileUrl {
                model.fileUrl = FileUrl(fileId: old.fileId, url: file.storedUrl, location: .newCloud, module: old.module, relativeUrl: nil, contentHash: old.contentHash)
            }
            replace(model: model, isInsert: false, forceSave: true)
            movedIds.append(move.id)
        }
        return movedIds
    }
}
