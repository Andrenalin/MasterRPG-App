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

    /// Copies `source` file-to-file to a new `.newCloud` file named after `relativeUrl` and hashes
    /// the copy streamed. Duplicating an item used to read its whole file into memory. Data held
    /// only in memory (unconverted) still goes through `createNewFileUrl`.
    /// The destination never replaces an existing file: a taken name gets a numbered suffix, and
    /// a destination that is the source itself is refused. The source is read from where the file
    /// really is on this device, not from bytes a game peer sent.
    /// Returns `nil` when the source file can't be resolved.
    /// See CODE_AUDIT_19 §7.1, CODE_AUDIT_20 §5.1.
    @concurrent
    func copyFile(_ source: FileUrl, fileId: UUID, to requestedUrl: URL) async throws -> FileUrl? {
        // Choosing a free name and copying are two steps, so a second copy can take the same
        // name in between. The copy itself never replaces a file: a collision fails and the next
        // free name is tried. See CODE_AUDIT_Folder §3.18.
        for attempt in 1...Self.maximumCopyNameAttempts {
            let relativeUrl = try await uniqueDestination(for: requestedUrl)
            do {
                return try await copyFile(source, fileId: fileId, toFreeName: relativeUrl)
            } catch let error as CocoaError where error.code == .fileWriteFileExists && attempt < Self.maximumCopyNameAttempts {
                continue
            }
        }
        throw CocoaError(.fileWriteFileExists)
    }

    private static let maximumCopyNameAttempts = 5

    private func copyFile(_ source: FileUrl, fileId: UUID, toFreeName relativeUrl: URL) async throws -> FileUrl? {
        if source.hasUnconvertedData {
            guard let data = try await loadData(for: source) else { return nil }
            var unconverted = FileUrl(fileId: fileId, url: relativeUrl, location: .newCloud, module: source.module, relativeUrl: nil)
            unconverted.resetData(data)
            return try await createNewFileUrl(fileId: fileId, unconvertedFileUrl: unconverted, pathExtension: relativeUrl.pathExtension)
        }

        let fullUrl = cloudDocumentController.fullUrl(fileUrl: relativeUrl)
        let nameUrl = cloudDocumentController.nameUrl(fullUrl: fullUrl)
        let filePath = nameUrl.path(percentEncoded: false)
        let cloudDocumentController = cloudDocumentController
        let destinationPath = Self.normalizedPath(fullUrl)
        let copied = try await deviceUrl(for: source) { sourceUrl async throws -> Bool? in
            guard let sourceUrl else { return false }
            guard Self.normalizedPath(sourceUrl) != destinationPath else {
                throw CocoaError(.fileWriteFileExists)
            }
            try await cloudDocumentController.copyWithoutReplacing(from: sourceUrl, to: filePath)
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

    /// `requestedUrl` (a path below the module folder), renamed with a numbered suffix when a
    /// file of that name already exists.
    private func uniqueDestination(for requestedUrl: URL) async throws -> URL {
        let folder = requestedUrl.deletingLastPathComponent().path(percentEncoded: false)
        let name = try await cloudDocumentController.suggestedFileName(for: folder, filename: requestedUrl.lastPathComponent)
        guard name != requestedUrl.lastPathComponent else { return requestedUrl }
        return requestedUrl.deletingLastPathComponent().appending(component: name)
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
        // Bytes a game peer sent for this file are of no use once the item is gone.
        peerFiles.remove(fileUrl.fileId)
        switch fileUrl.location {
            case .local, .appCloud, .newCloud:
                Task { @concurrent in
                    await CloudKitOperationCounter.shared.recordOperation(function: "FileUrlDataController.delete(_:)", file: "FileUrlDataController.swift")

                    // The real file, never the temp copy of held peer bytes. See CODE_AUDIT_20 §5.3.
                    guard let accessUrl = await deviceUrl(for: fileUrl, action: { $0 }) else { return }
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

    /// Where the app stores the file `fileUrl` points to, or `nil` for references it does not
    /// own (`.icloud`, `.other`). The single notion of "where the file really is" that
    /// `deleteReplaced` and `isSameStoredFile` compare. See CODE_AUDIT_20 §5.9.
    func storedLocation(of fileUrl: FileUrl) -> URL? {
        switch fileUrl.location {
        case .newCloud:
            return cloudDocumentController.fullUrl(fileUrl: fileUrl.rawUrl)
        case .local, .appCloud:
            return locationFileManager.absoluteUrl(for: fileUrl.rawUrl, at: fileUrl.location, module: fileUrl.module)
        case .url:
            return remoteCacheURL(for: fileUrl)
        case .icloud, .other:
            return nil
        }
    }

    /// Removes the file `fileUrl` points at, found by its path; bookmarks are left alone. For
    /// files an import wrote that no item references. See CODE_AUDIT_Folder §5.26.
    func removeStoredFile(_ fileUrl: FileUrl) async {
        guard let location = storedLocation(of: fileUrl) else { return }
        _ = await removeFileLoggingFailure(at: location)
    }

    /// Where imported bytes for `fileUrl` are written. The sender's relative path is used when
    /// nothing is there, or when the file there already holds exactly these bytes and no item
    /// in `referencedFileUrls` uses it (it is then reused, not rewritten). Otherwise the next
    /// free name in the same folder is taken: imported bytes used to overwrite whatever file
    /// had that name, including another item's file or a newer local version.
    /// See CODE_AUDIT_Folder §5.2.
    func importDestination(for fileUrl: FileUrl, contentHash: String, referencedFileUrls: [FileUrl]) async throws -> FileUrl {
        guard fileUrl.location != .url else { return fileUrl }
        let destination = cloudDocumentController.fullUrl(fileUrl: fileUrl.rawUrl)
        let (exists, _) = try await FileManager.default.fileExists(coordinatingAccessAt: destination)
        guard exists else { return fileUrl }
        let destinationPath = Self.normalizedPath(destination)
        let isReferenced = referencedFileUrls.contains { referenced in
            storedLocation(of: referenced).map { Self.normalizedPath($0) == destinationPath } ?? false
        }
        if !isReferenced,
           let existingHash = try? await FileManager.default.contentHash(coordinatingAccessAt: destination),
           existingHash == contentHash {
            return fileUrl
        }
        let relative = cloudDocumentController.nameUrl(fullUrl: destination)
        let folder = relative.deletingLastPathComponent().path(percentEncoded: false)
        let name = try await cloudDocumentController.suggestedFileName(for: folder, filename: relative.lastPathComponent)
        return FileUrl(
            fileId: fileUrl.fileId,
            url: relative.deletingLastPathComponent().appending(component: name),
            location: .newCloud,
            module: fileUrl.module,
            relativeUrl: nil,
            contentHash: fileUrl.contentHash
        )
    }

    /// Whether two references resolve to the same stored file.
    func isSameStoredFile(_ lhs: FileUrl, _ rhs: FileUrl) -> Bool {
        guard let lhsLocation = storedLocation(of: lhs), let rhsLocation = storedLocation(of: rhs) else { return false }
        return Self.normalizedPath(lhsLocation) == Self.normalizedPath(rhsLocation)
    }

    private static func normalizedPath(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path(percentEncoded: false)
    }

    /// Deletes a file an item's new file just replaced. The replacement already saved its
    /// bookmark under the same `fileId`, so the old file is found by its path, never through
    /// the bookmark (that would resolve to the new file), and the bookmark is kept. Nothing is
    /// deleted when the new reference resolves to the old file's location.
    /// See CODE_AUDIT_19 §5.9, CODE_AUDIT_20 §5.9.
    func deleteReplaced(_ fileUrl: FileUrl, keeping newFileUrl: FileUrl) async {
        guard let fileLocation = storedLocation(of: fileUrl) else { return }
        if let newLocation = storedLocation(of: newFileUrl), Self.normalizedPath(newLocation) == Self.normalizedPath(fileLocation) {
            return
        }
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
