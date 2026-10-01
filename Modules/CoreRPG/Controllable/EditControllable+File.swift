// @copyright André Trettin

import SwiftUI
import os.log

// Split out of EditControllable.swift so file-replacement fixes (CODE_AUDIT_20 §5.1, §5.4,
// §5.9) do not keep growing the largest file. See CODE_AUDIT_20 §9.18.

// MARK: - Files

public extension EditControllable {
    @MainActor func folderPath(itemId: UUID?) async -> String {
        guard let itemId, let item = editModel(for: itemId) else { return "" }
        var name = ""
        if let parentId = item.parentId {
            name = await folderPath(itemId: parentId) + "/"
        }
        name.append(item.name)
        return name
    }
    
    @MainActor func movedFile(itemId: UUID) {
        Task {
            guard let fileUrlDataController, let item = editModel(for: itemId), let oldFileUrl = item.fileUrl, item.displayState != DisplayStateMask.totalHidden.rawValue else { return }
            let path = await folderPath(itemId: itemId)
            let newFileUrl = await fileUrlDataController.move(fileUrl: oldFileUrl, to: path)
            if let newFileUrl {
                reset(fileUrl: newFileUrl, itemId: item.id)
            }
        }
    }
    
    @MainActor func resetFile(url: URL?, itemId: UUID) async {
        guard let fileUrlDataController, let item = editModel(for: itemId) else { return }

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

        guard !isSameFilePath else { return }
        guard let url else {
            // The file was removed, not replaced.
            if let replacedFileUrl {
                fileUrlDataController.delete(replacedFileUrl)
                reset(fileUrl: nil, itemId: itemId)
            }
            return
        }

        let securityScope = url.startSecurityScopedAccess()
        defer { securityScope.stop() }

        if item.name.isEmpty {
            let ext = url.pathExtension.isEmpty ? "" : ".\(url.pathExtension)"
            let name = url.lastPathComponent.replacing(ext, with: "")
            reset(name: name, itemId: itemId)
        }

        do {
            // Create the new file before the old one is deleted: a failed replacement (iCloud
            // copy error, scope failure) used to leave the item with no file on every device.
            // See CODE_AUDIT_19 §5.9.
            let updatedFileUrl = try await fileUrlDataController.createFileUrl(fileId: itemId, url: url, module: itemControllable.config.module.token, category: folderPath(itemId: item.parentId))
            reset(fileUrl: updatedFileUrl, itemId: itemId)
            if let replacedFileUrl {
                await fileUrlDataController.deleteReplaced(replacedFileUrl, keeping: updatedFileUrl)
                if updatedFileUrl.location == .url {
                    // A remote file saves no bookmark, so the old one is stale.
                    fileUrlDataController.removeBookmarks(fileId: itemId)
                }
            }
        } catch {
            // The old file and its reference are kept. Log and surface the failure so the
            // user learns the attach failed. See CODE_AUDIT_EditItem §5.7, CODE_AUDIT_19 §5.9.
            Logger.editController.error("resetFile(url:itemId:) failed to create file url: \(error.localizedDescription, privacy: .public)")
            itemControllable.itemDataModel.lastPersistenceError = error
            PersistenceIssueCenter.shared.recordFileError(error)
        }
    }
    
    /// Gives `itemId` its own copy of `source`, named like `resetFile(data:itemId:path:)` names
    /// new files, copied file-to-file. See CODE_AUDIT_19 §7.1.
    @MainActor func resetFile(copying source: FileUrl, itemId: UUID) async throws {
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
        reset(fileUrl: fileUrl, itemId: itemId)
    }

    /// Replaces the item's file with `data`. The new file is written before the old one is
    /// deleted, durably (a write failure throws and keeps the old file instead of falling back
    /// to memory-only bytes), and the old file is never deleted when the new one resolves to the
    /// same location. See CODE_AUDIT_20 §5.4.
    @MainActor func resetFile(data: Data?, itemId: UUID, path: String) async throws {
        guard let item = editModel(for: itemId) else { return }
        let replacedFileUrl = item.fileUrl
        guard let data else {
            if replacedFileUrl != nil {
                await resetFile(url: nil, itemId: itemId)
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
        let dataUrl = URL(string: "/")!.appending(path: folder).appending(component: fileName)
        var dataFileUrl = FileUrl(fileId: item.id, url: dataUrl, location: .newCloud, module: module, relativeUrl: nil)
        dataFileUrl.resetData(data)

        guard let fileUrlDataController else { return }
        guard let fileUrl = try await fileUrlDataController.createNewFileUrl(fileId: item.id, unconvertedFileUrl: dataFileUrl, pathExtension: itemControllable.config.filenameExtension, requireDurableStorage: true) else {
            throw CocoaError(.fileWriteUnknown)
        }
        await itemControllable.cacheControllable?.remove(itemId: itemId, includeImage: true)
        reset(fileUrl: fileUrl, itemId: itemId)
        if let replacedFileUrl {
            await fileUrlDataController.deleteReplaced(replacedFileUrl, keeping: fileUrl)
        }
    }
}
