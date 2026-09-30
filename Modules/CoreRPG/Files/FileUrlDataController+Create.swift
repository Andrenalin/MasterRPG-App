// @copyright André Trettin

import Combine
import CryptoKit
import SwiftUI
import UniformTypeIdentifiers
import os.log
import Synchronization

// Split out of FileUrlDataController.swift — see CODE_AUDIT_19 §9.23.

public extension FileUrlDataController {
    /// create a fileUrl with data from an import or on validation / convert data.
    /// `@concurrent`: hashing and writing whole files must not run on the caller's (main) actor.
    /// See CODE_AUDIT_15 §3.12.
    @concurrent
    func createNewFileUrl(
        fileId: UUID,
        unconvertedFileUrl: FileUrl,
        pathExtension: String,
        requireDurableStorage: Bool = false
    ) async throws -> FileUrl? {
        await CloudKitOperationCounter.shared.recordOperation(function: "FileUrlDataController.createNewFileUrl(fileId:unconvertedFileUrl:pathExtension:)", file: "FileUrlDataController.swift")
        
        guard let oldData = unconvertedFileUrl.data else { return nil }
        if unconvertedFileUrl.location == .url {
            return try await cacheRemoteData(
                oldData,
                fileId: fileId,
                source: unconvertedFileUrl
            )
        }
        let contentHash = unconvertedFileUrl.contentHash ?? FileUrl.contentHash(of: oldData)

        if let oldUrl = locationFileManager.absoluteUrl(for: unconvertedFileUrl.rawUrl, at: unconvertedFileUrl.location, module: unconvertedFileUrl.module) {
            do {
                // Try the stored legacy location before rewriting imported bytes.
                let (exists, isDir) = try await FileManager.default.fileExists(coordinatingAccessAt: oldUrl)
                if exists && !isDir {
                    // Streamed, not read into memory. See CODE_AUDIT_19 §7.1.
                    if let existingHash = try? await FileManager.default.contentHash(coordinatingAccessAt: oldUrl),
                       existingHash == contentHash {
                        // File already exists on disk - return FileUrl without data in memory
                        return FileUrl(fileId: fileId, url: unconvertedFileUrl.rawUrl, location: unconvertedFileUrl.location, module: unconvertedFileUrl.module, relativeUrl: nil, contentHash: contentHash)
                    }
                }
            } catch {
                Logger.fileStore.error("Different device or different user \(error.localizedDescription, privacy: .public)")
            }
        }

        let fullUrl = cloudDocumentController.fullUrl(fileUrl: unconvertedFileUrl.rawUrl)
        let fileURL = cloudDocumentController.nameUrl(fullUrl: fullUrl)
        let filePath = fileURL.path(percentEncoded: false)

        do {
            // Write uses batched coordination internally now (createDirectory + write)
            try await cloudDocumentController.write(data: oldData, to: filePath)
        } catch {
            Logger.fileStore.error("Cannot create file in cloud app group \(error.localizedDescription, privacy: .public)")
            if requireDurableStorage {
                throw error
            }
            // Fallback: Keep data in memory when cloud storage fails
            var fileUrl = FileUrl(fileId: fileId, url: fileURL, location: .newCloud, module: unconvertedFileUrl.module, relativeUrl: nil)
            fileUrl.resetData(oldData)
            Logger.fileStore.info("Keeping file data in memory as fallback")
            return fileUrl
        }

        // Bookmark without additional coordination (just security-scoped access)
        let securityScope = fullUrl.startSecurityScopedAccess()
        defer { securityScope.stop() }
        do {
            try await fileBookmarkController.saveBookmark(fileId: fileId, fileUrl: fullUrl)
        } catch {
            Logger.fileStore.error("Cannot bookmark file \(error.localizedDescription, privacy: .public)")
        }
        return FileUrl(fileId: fileId, url: fileURL, location: .newCloud, module: unconvertedFileUrl.module, relativeUrl: nil, contentHash: contentHash)
    }

    /// Copies `source` file-to-file to the `.newCloud` file at `relativeUrl` and hashes the copy
    /// streamed. Duplicating an item used to read its whole file into memory. Data held only in
    /// memory (unconverted or a peer's file) still goes through `createNewFileUrl`.
    /// Returns `nil` when the source file can't be resolved. See CODE_AUDIT_19 §7.1.
    @concurrent
    func copyFile(_ source: FileUrl, fileId: UUID, to relativeUrl: URL) async throws -> FileUrl? {
        if source.hasUnconvertedData || peerFiles.data(for: source.fileId) != nil {
            guard let data = try await loadData(for: source) else { return nil }
            var unconverted = FileUrl(fileId: fileId, url: relativeUrl, location: .newCloud, module: source.module, relativeUrl: nil)
            unconverted.resetData(data)
            return try await createNewFileUrl(fileId: fileId, unconvertedFileUrl: unconverted, pathExtension: relativeUrl.pathExtension)
        }

        let fullUrl = cloudDocumentController.fullUrl(fileUrl: relativeUrl)
        let nameUrl = cloudDocumentController.nameUrl(fullUrl: fullUrl)
        let filePath = nameUrl.path(percentEncoded: false)
        let cloudDocumentController = cloudDocumentController
        let copied = try await url(for: source) { sourceUrl async throws -> Bool? in
            guard let sourceUrl else { return false }
            try await cloudDocumentController.copy(from: sourceUrl, to: filePath)
            return true
        }
        guard copied == true else { return nil }

        let securityScope = fullUrl.startSecurityScopedAccess()
        defer { securityScope.stop() }
        do {
            try await fileBookmarkController.saveBookmark(fileId: fileId, fileUrl: fullUrl)
        } catch {
            Logger.fileStore.error("Cannot bookmark file \(error.localizedDescription, privacy: .public)")
        }
        let contentHash = try await FileManager.default.contentHash(coordinatingAccessAt: fullUrl)
        return FileUrl(fileId: fileId, url: nameUrl, location: .newCloud, module: source.module, relativeUrl: nil, contentHash: contentHash)
    }

    /// ItemController will call to get FileUrl for given urls from picker
    @concurrent
    func createFileUrl(fileId: UUID, url: URL, module: String, category: String?, contentHash: String? = nil) async throws -> FileUrl {
        await CloudKitOperationCounter.shared.recordOperation(function: "FileUrlDataController.createFileUrl(fileId:url:module:category:)", file: "FileUrlDataController.swift")

        if url.isSupportedRemoteFileUrl {
            return FileUrl(
                fileId: fileId,
                url: url,
                location: .url,
                module: module,
                relativeUrl: nil,
                contentHash: contentHash
            )
        }

        do {
            let values = try url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
            if values.ubiquitousItemDownloadingStatus != .current {
                // Routed through the file-coordinated helper (not a direct, uncoordinated
                // `FileManager.default.startDownloadingUbiquitousItem` call) to avoid racing
                // CloudKit sync's own coordinator-protected access to this URL, and logged on
                // failure like the neighboring `resourceValues` failure path below instead of
                // being silently discarded. See CODE_AUDIT §9.6.
                try await FileManager.default.download(coordinatingAccessAt: url)
            }
        } catch {
            Logger.fileStore.error("Cannot get the download status of url \(url.absoluteString, privacy: .private)")
        }
        let fullUrl = try await cloudDocumentController.createNameUrl(for: url)
        try await fileBookmarkController.saveBookmark(fileId: fileId, fileUrl: fullUrl)
        let nameUrl = cloudDocumentController.nameUrl(fullUrl: fullUrl)
        // Compute a contentHash from the picker's file data when the caller didn't already
        // supply one — this path used to always persist `contentHash == nil` for picker-added
        // files while `createNewFileUrl` (the import path) always populated it, forcing
        // picker-added files onto a weaker CloudKit version-determinism fallback than
        // imported ones. See CODE_AUDIT §5.5.
        let resolvedContentHash: String?
        if let contentHash {
            resolvedContentHash = contentHash
        } else {
            do {
                // Streamed, not read into memory. See CODE_AUDIT_19 §7.1.
                resolvedContentHash = try await FileManager.default.contentHash(coordinatingAccessAt: url)
            } catch {
                Logger.fileStore.error("Cannot read picker file to compute contentHash \(error.localizedDescription, privacy: .public)")
                resolvedContentHash = nil
            }
        }
        return FileUrl(fileId: fileId, url: nameUrl, location: .newCloud, module: module, relativeUrl: nil, contentHash: resolvedContentHash)
    }

    /// Check if the new URL points to the same file as the existing FileUrl
    func isSameFile(existingFileUrl: FileUrl, newUrl: URL?) async -> Bool {
        guard let newUrl else { return false }
        if existingFileUrl.location == .url || newUrl.isSupportedRemoteFileUrl {
            return existingFileUrl.rawUrl.absoluteString == newUrl.absoluteString
        }

        // Quick path comparison first (fast path for obvious matches)
        let nameUrl = cloudDocumentController.nameUrl(fullUrl: newUrl)
        if existingFileUrl.rawUrl.path() == nameUrl.path() {
            return true
        }

        // Check file identity using resource identifiers (reliable method)
        return await url(for: existingFileUrl) { existingUrl in
            guard let existingUrl else { return false }
            do {
                // Get file resource identifiers for both URLs
                let existingValues = try existingUrl.resourceValues(forKeys: [.fileResourceIdentifierKey])
                let newValues = try newUrl.resourceValues(forKeys: [.fileResourceIdentifierKey])
                
                // Compare the actual file identifiers
                guard let existingId = existingValues.fileResourceIdentifier,
                      let newId = newValues.fileResourceIdentifier else {
                    return false
                }
                
                return existingId.isEqual(newId)
            } catch {
                Logger.fileStore.debug("Cannot compare file identifiers: \(error.localizedDescription, privacy: .public)")
                return false
            }
        } ?? false
    }

    /// called from ItemStore on delete of the item
    func delete(_ fileUrl: FileUrl?) {
        guard let fileUrl else { return }
        switch fileUrl.location {
            case .local, .appCloud, .newCloud:
                Task { @concurrent in
                    await CloudKitOperationCounter.shared.recordOperation(function: "FileUrlDataController.delete(_:)", file: "FileUrlDataController.swift")

                    guard let accessUrl = await url(for: fileUrl, action: { $0 }) else { return }
                    // Only drop the bookmark once the file is actually gone (or was
                    // already gone) — a genuine removal failure (coordination
                    // timeout, permission error, transient iCloud state) instead
                    // keeps the bookmark so the file isn't silently orphaned with
                    // nothing left referencing it. See CODE_AUDIT §5.3.
                    guard await removeFileLoggingFailure(at: accessUrl) else { return }
                    fileBookmarkController.removeBookmark(fileId: fileUrl.fileId)
                }
            case .url:
                Task { @concurrent in
                    let cacheURL = remoteCacheURL(for: fileUrl)
                    guard await removeFileLoggingFailure(at: cacheURL) else { return }
                    fileBookmarkController.removeBookmark(fileId: fileUrl.fileId)
                }
            case .icloud, .other:
                fileBookmarkController.removeBookmark(fileId: fileUrl.fileId)
                break
        }
    }

    /// Deletes a file an item's new file just replaced. The replacement already saved its
    /// bookmark under the same `fileId`, so the old file is found by its path, never through
    /// the bookmark (that would resolve to the new file), and the bookmark is kept.
    /// See CODE_AUDIT_19 §5.9.
    func deleteReplaced(_ fileUrl: FileUrl) async {
        let fileLocation: URL?
        switch fileUrl.location {
        case .newCloud:
            fileLocation = cloudDocumentController.fullUrl(fileUrl: fileUrl.rawUrl)
        case .local, .appCloud:
            fileLocation = locationFileManager.absoluteUrl(for: fileUrl.rawUrl, at: fileUrl.location, module: fileUrl.module)
        case .url:
            fileLocation = remoteCacheURL(for: fileUrl)
        case .icloud, .other:
            // Not stored by the app; `delete(_:)` only drops the bookmark for these.
            fileLocation = nil
        }
        guard let fileLocation else { return }
        _ = await removeFileLoggingFailure(at: fileLocation)
    }

    /// Removes the file at `url`, logging (rather than silently discarding)
    /// any failure other than the file already being absent. Returns `true`
    /// when the caller may safely treat the file as gone — either it was
    /// actually removed, or it didn't exist in the first place — and `false`
    /// when a real error occurred and the caller should keep whatever
    /// reference (e.g. a bookmark) it was about to drop, so the file isn't
    /// silently orphaned. See CODE_AUDIT §5.3.
    private func removeFileLoggingFailure(at url: URL) async -> Bool {
        do {
            try await FileManager.default.removeItem(coordinatingAccessAt: url)
            return true
        } catch {
            guard (error as NSError).code == NSFileNoSuchFileError else {
                Logger.fileStore.error("Cannot delete file, keeping bookmark for retry \(error.localizedDescription, privacy: .public)")
                return false
            }
            return true
        }
    }

    func removeBookmarks(fileId: UUID) {
        fileBookmarkController.removeBookmark(fileId: fileId)
    }

    func download(fileUrl: FileUrl) async throws {
        await CloudKitOperationCounter.shared.recordOperation(function: "FileUrlDataController.download(fileUrl:)", file: "FileUrlDataController.swift")
        
        if fileUrl.location == .newCloud {
            try await cloudDocumentController.download(filePath: fileUrl.rawUrl.absoluteString)
        } else if fileUrl.location == .url {
            _ = try await ensureRemoteCache(for: fileUrl)
        }
    }

    func duplicate(fileUrl: FileUrl?, for fileId: UUID) async throws -> FileUrl? {
        await CloudKitOperationCounter.shared.recordOperation(function: "FileUrlDataController.duplicate(fileUrl:for:)", file: "FileUrlDataController.swift")
        
        do {
            guard var unconverted = fileUrl, let data = try await loadData(for: unconverted) else { return nil }
            unconverted.resetData(data)
            return try await createNewFileUrl(fileId: fileId, unconvertedFileUrl: unconverted, pathExtension: filenameExtension)
        } catch {
            let nsError = error as NSError
            let missingFileCodes = [NSFileNoSuchFileError, NSFileReadNoSuchFileError]
            guard nsError.domain == NSCocoaErrorDomain && missingFileCodes.contains(nsError.code) else {
                throw error
            }
            return nil
        }
    }
}
