// @copyright André Trettin

import SwiftUI
import os.log

// Split out of EditControllable.swift so file-replacement fixes (CODE_AUDIT_20 §5.1, §5.4,
// §5.9) do not keep growing the largest file. See CODE_AUDIT_20 §9.18.

// MARK: - Files

public extension EditControllable {
    /// The item's path below the module folder: its folder names and its own name. Walks up the
    /// `parentId` chain iteratively with a cycle guard; a parent cycle from imported or merged
    /// data recursed until the stack overflowed. See CODE_AUDIT_Folder §5.30.
    @MainActor func folderPath(itemId: UUID?) async -> String {
        var names: [String] = []
        var visited: Set<UUID> = []
        var currentId = itemId
        while let id = currentId, visited.count < FolderTreeDepthLimit.max, visited.insert(id).inserted,
              let item = editModel(for: id) {
            names.append(item.name)
            currentId = item.parentId
        }
        return names.reversed().joined(separator: "/")
    }
    
    /// Queues `operation` behind every file operation already queued for `itemId` and returns its
    /// task. Registration is synchronous, so operations run in call order. An operation must not
    /// await another queued operation for the same item, or it waits on itself.
    /// See CODE_AUDIT_Folder §3.8, §3.19.
    @MainActor func enqueueFileOperation<T: Sendable>(
        itemId: UUID,
        _ operation: @escaping @MainActor @Sendable () async throws -> T
    ) -> Task<T, any Error> {
        let previous = editorModel.fileOperationTails[itemId]?.task
        let task = Task { @MainActor () async throws -> T in
            await previous?.value
            return try await operation()
        }
        let token = UUID()
        let editorModel = editorModel
        let tail = Task { @MainActor in
            _ = await task.result
            if editorModel.fileOperationTails[itemId]?.token == token {
                editorModel.fileOperationTails[itemId] = nil
            }
        }
        editorModel.fileOperationTails[itemId] = (token, tail)
        return task
    }

    /// Moves the item's file to match its folder. Queued per item, so two quick moves end in the
    /// final folder, and the item is re-read after the move. See CODE_AUDIT_Folder §3.8.
    @MainActor func movedFile(itemId: UUID) {
        _ = enqueueFileOperation(itemId: itemId) {
            await moveFileToFolderPath(itemId: itemId)
        }
    }

    @MainActor private func moveFileToFolderPath(itemId: UUID) async {
        guard let fileUrlDataController,
              let item = itemControllable.itemSync(for: itemId, noGame: true),
              let oldFileUrl = item.fileUrl,
              item.displayState != DisplayStateMask.totalHidden.rawValue else { return }
        let path = await folderPath(itemId: itemId)
        let newFileUrl: FileUrl?
        do {
            newFileUrl = try await fileUrlDataController.move(fileUrl: oldFileUrl, to: path)
        } catch {
            Logger.editController.error("movedFile(itemId:) failed to move the file: \(error.localizedDescription, privacy: .private)")
            itemControllable.itemDataModel.lastPersistenceError = error
            PersistenceIssueCenter.shared.recordFileError(error)
            return
        }
        guard let newFileUrl else { return }
        guard let current = itemControllable.itemSync(for: itemId, noGame: true) else {
            // Deleted while its file moved: the delete removed the old path, so the moved
            // file would be left with no item.
            fileUrlDataController.delete(newFileUrl)
            return
        }
        guard current.fileUrl == oldFileUrl else { return }
        // The move on disk is real, so the new path is persisted also during a running game.
        // See CODE_AUDIT_Folder §5.21.
        itemControllable.persistFileUrl(newFileUrl, itemId: itemId)
    }

    /// Replaces the item's file with the file at `url`, or removes it when `url` is nil. Queued
    /// with the item's other file operations. See CODE_AUDIT_Folder §3.19.
    ///
    /// Returns whether the item has the requested file afterwards. A caller that owns the
    /// source (the 3D scanner and its scan folder) must keep it when this is `false`.
    /// See CODE_AUDIT_21 §5.21.
    @MainActor @discardableResult func resetFile(url: URL?, itemId: UUID) async -> Bool {
        let result = await enqueueFileOperation(itemId: itemId) {
            await replaceFile(url: url, itemId: itemId)
        }.result
        return (try? result.get()) ?? false
    }

    /// The body of `resetFile(url:itemId:)`; callers that already run inside a queued file
    /// operation for `itemId` call this directly.
    @MainActor private func replaceFile(url: URL?, itemId: UUID) async -> Bool {
        guard let fileUrlDataController, let item = editModel(for: itemId) else { return false }

        // Check if we have an existing file
        var isSameFilePath: Bool = false
        var replacedFileUrl: FileUrl?
        if let existingFileUrl = item.fileUrl {
            // If selecting same file, just reset cache without deleting
            isSameFilePath = await fileUrlDataController.isSameFile(existingFileUrl: existingFileUrl, newUrl: url)
            // reset cach only for the thumbnail, it might be old thumbnail file exists.
            await itemControllable.cacheControllable?.remove(itemId: itemId, includeImage: !isSameFilePath)
            if !isSameFilePath {
                replacedFileUrl = existingFileUrl
            }
        }

        guard !isSameFilePath else { return true }
        guard let url else {
            // The file was removed, not replaced.
            if let replacedFileUrl {
                fileUrlDataController.delete(replacedFileUrl, keepingStoredFile: itemControllable.isFileUsedElsewhere(replacedFileUrl, excluding: itemId))
                reset(fileUrl: nil, itemId: itemId)
            }
            return true
        }

        let securityScope = url.startSecurityScopedAccess()
        defer { securityScope.stop() }

        // Re-read: a name typed while the awaits above ran must not be replaced by the file name.
        if editModel(for: itemId)?.name.isEmpty == true {
            let ext = url.pathExtension.isEmpty ? "" : ".\(url.pathExtension)"
            let name = url.lastPathComponent.replacing(ext, with: "")
            reset(name: name, itemId: itemId)
        }

        do {
            // Create the new file before the old one is deleted: a failed replacement (iCloud
            // copy error, scope failure) used to leave the item with no file on every device.
            // See CODE_AUDIT_19 §5.9.
            let updatedFileUrl = try await fileUrlDataController.createFileUrl(fileId: itemId, url: url, module: itemControllable.config.module.token, category: folderPath(itemId: item.parentId))
            guard editModel(for: itemId) != nil else {
                // Deleted while the new file was created: nothing would reference it.
                fileUrlDataController.delete(updatedFileUrl)
                return false
            }
            reset(fileUrl: updatedFileUrl, itemId: itemId)
            if let replacedFileUrl {
                if !itemControllable.isFileUsedElsewhere(replacedFileUrl, excluding: itemId) {
                    await fileUrlDataController.deleteReplaced(replacedFileUrl, keeping: updatedFileUrl)
                }
                if updatedFileUrl.location == .url {
                    // A remote file saves no bookmark, so the old one is stale.
                    fileUrlDataController.removeBookmarks(fileId: itemId)
                }
            }
            return true
        } catch {
            // The old file and its reference are kept. Log and surface the failure so the
            // user learns the attach failed. See CODE_AUDIT_EditItem §5.7, CODE_AUDIT_19 §5.9.
            Logger.editController.error("resetFile(url:itemId:) failed to create file url: \(error.localizedDescription, privacy: .private)")
            itemControllable.itemDataModel.lastPersistenceError = error
            PersistenceIssueCenter.shared.recordFileError(error)
            return false
        }
    }
    
    /// Gives `itemId` its own copy of `source`, named like `resetFile(data:itemId:path:)` names
    /// new files, copied file-to-file. See CODE_AUDIT_19 §7.1.
    @MainActor func resetFile(copying source: FileUrl, itemId: UUID) async throws {
        try await enqueueFileOperation(itemId: itemId) {
            try await copyFile(source, itemId: itemId)
        }.value
    }

    @MainActor private func copyFile(_ source: FileUrl, itemId: UUID) async throws {
        guard let fileUrlDataController, let item = editModel(for: itemId) else { return }
        var folder = await folderPath(itemId: item.parentId)
        if !folder.isEmpty {
            folder.append("/")
        }
        let baseName = item.name.isEmpty ? "NewData-\(item.id.uuidString)" : item.name
        let fileName = "\(baseName).\(itemControllable.config.filenameExtension)"
        guard let root = URL(string: "/") else { return }
        let destination = root.appending(path: folder).appending(component: fileName)
        guard let fileUrl = try await fileUrlDataController.copyFile(source, fileId: item.id, to: destination) else {
            throw CocoaError(.fileNoSuchFile)
        }
        // A duplicate is persisted also during a running game, and so is its copied file.
        // See CODE_AUDIT_Folder §5.21.
        itemControllable.persistFileUrl(fileUrl, itemId: itemId)
    }

    /// Replaces the item's file with `data`. The new file is written before the old one is
    /// deleted, durably (a write failure throws and keeps the old file instead of falling back
    /// to memory-only bytes), and the old file is never deleted when the new one resolves to the
    /// same location, or when another item uses it. The file is named after the item; a name
    /// another item's file already has gets a numbered suffix instead of overwriting that file.
    /// See CODE_AUDIT_20 §5.4, CODE_AUDIT_21 §5.2.
    @MainActor func resetFile(data: Data?, itemId: UUID, path: String) async throws {
        try await enqueueFileOperation(itemId: itemId) {
            try await writeFile(data: data, itemId: itemId)
        }.value
    }

    @MainActor private func writeFile(data: Data?, itemId: UUID) async throws {
        guard let item = editModel(for: itemId) else { return }
        let replacedFileUrl = item.fileUrl
        guard let data else {
            if replacedFileUrl != nil {
                // Already inside this item's queued file operation; calling the queued
                // `resetFile(url:itemId:)` here would wait on itself.
                _ = await replaceFile(url: nil, itemId: itemId)
            }
            return
        }

        let module = itemControllable.config.module.token
        var folder = await folderPath(itemId: item.parentId)
        if !folder.isEmpty {
            folder.append("/")
        }
        let baseName = item.name.isEmpty ? "NewData-\(item.id.uuidString)" : item.name
        let fileName = "\(baseName).\(itemControllable.config.filenameExtension)"
        // `baseName` comes from a user-editable item name, which can contain characters
        // (`#`, unencoded `%`/`?`, ...) that aren't valid in a URL string; `.appending(component:)`
        // percent-encodes it so this can never fail, unlike `URL(string:)!`.
        let requestedUrl = URL(string: "/")!.appending(path: folder).appending(component: fileName)
        guard let fileUrlDataController else { return }
        let dataUrl = try await fileUrlDataController.writeDestination(
            for: requestedUrl,
            replacing: replacedFileUrl,
            referencedFileUrls: itemControllable.libraryFileUrls(excluding: itemId)
        )
        var dataFileUrl = FileUrl(fileId: item.id, url: dataUrl, location: .newCloud, module: module, relativeUrl: nil)
        dataFileUrl.resetData(data)

        guard let fileUrl = try await fileUrlDataController.createNewFileUrl(fileId: item.id, unconvertedFileUrl: dataFileUrl, pathExtension: itemControllable.config.filenameExtension, requireDurableStorage: true) else {
            throw CocoaError(.fileWriteUnknown)
        }
        await itemControllable.cacheControllable?.remove(itemId: itemId, includeImage: true)
        reset(fileUrl: fileUrl, itemId: itemId)
        if let replacedFileUrl, !itemControllable.isFileUsedElsewhere(replacedFileUrl, excluding: itemId) {
            await fileUrlDataController.deleteReplaced(replacedFileUrl, keeping: fileUrl)
        }
    }
}
