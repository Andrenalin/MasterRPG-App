// @copyright André Trettin

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
            // A deletion of this file that is still queued would remove it after it was reused.
            // See CODE_AUDIT_21 §3.6.
            await waitForPendingDeletion(at: oldUrl)
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
                Logger.fileStore.error("Different device or different user \(error.logIdentifier, privacy: .public) \(error.localizedDescription, privacy: .private)")
            }
        }

        // A url that names no file below the module folder (a bare folder, the container root of
        // another device) gets a name of its own; it used to resolve to the module folder.
        // See CODE_AUDIT_21 §5.1, §6.1.
        let fallbackName = pathExtension.isEmpty ? fileId.uuidString : "\(fileId.uuidString).\(pathExtension)"
        guard let fullUrl = cloudDocumentController.fullUrl(fileUrl: unconvertedFileUrl.rawUrl)
                ?? cloudDocumentController.fullUrl(filePath: fallbackName) else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        let fileURL = cloudDocumentController.nameUrl(fullUrl: fullUrl)
        let filePath = fileURL.path(percentEncoded: false)

        // Likewise a queued deletion of the destination would remove the file written now.
        await waitForPendingDeletion(at: fullUrl)
        do {
            // Write uses batched coordination internally now (createDirectory + write)
            try await cloudDocumentController.write(data: oldData, to: filePath)
        } catch {
            Logger.fileStore.error("Cannot create file in cloud app group \(error.logIdentifier, privacy: .public) \(error.localizedDescription, privacy: .private)")
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
            Logger.fileStore.error("Cannot bookmark file \(error.logIdentifier, privacy: .public) \(error.localizedDescription, privacy: .private)")
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

        guard let fullUrl = cloudDocumentController.fullUrl(fileUrl: relativeUrl) else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
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
            Logger.fileStore.error("Cannot bookmark file \(error.logIdentifier, privacy: .public) \(error.localizedDescription, privacy: .private)")
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

    /// Where new bytes for an item are written. `requestedUrl` is used when nothing is there, or
    /// when the file there is the item's own current file (`current`) and no item in
    /// `referencedFileUrls` shares it: it is then replaced in place. Any other taken name gets a
    /// numbered suffix. Item names are not unique, and a second photo named like the first used
    /// to overwrite, or silently share, the first one's file. See CODE_AUDIT_21 §5.2.
    func writeDestination(for requestedUrl: URL, replacing current: FileUrl?, referencedFileUrls: [FileUrl]) async throws -> URL {
        if let current, current.location == .newCloud,
           let currentLocation = storedLocation(of: current),
           let requestedLocation = cloudDocumentController.fullUrl(fileUrl: requestedUrl),
           Self.normalizedPath(currentLocation) == Self.normalizedPath(requestedLocation),
           !referencedFileUrls.contains(where: { isSameStoredFile($0, current) }) {
            return requestedUrl
        }
        return try await uniqueDestination(for: requestedUrl)
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
                Logger.fileStore.error("Cannot read picker file to compute contentHash \(error.logIdentifier, privacy: .public) \(error.localizedDescription, privacy: .private)")
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
                Logger.fileStore.debug("Cannot compare file identifiers: \(error.logIdentifier, privacy: .public) \(error.localizedDescription, privacy: .private)")
                return false
            }
        } ?? false
    }

    /// Announces that the stored file of `fileUrl` is about to be deleted, for a caller that
    /// takes the file's item out of memory now and only reaches `delete(_:)` after further
    /// suspensions. Pass the result to `delete(_:keepingStoredFile:announced:)`. `nil` for a
    /// reference the app stores no file for. See CODE_AUDIT_21 §3.6.
    func announceDeletion(of fileUrl: FileUrl?) -> PendingFileDeletions.Announcement? {
        guard let fileUrl, let location = storedLocation(of: fileUrl) else { return nil }
        return PendingFileDeletions.shared.announce(at: Self.normalizedPath(location))
    }

    /// called from ItemStore on delete of the item
    /// - Parameter keepingStoredFile: Another item still references the stored file, so only this
    ///   item's bookmark and held bytes go. See CODE_AUDIT_21 §5.2.
    /// - Parameter announced: The announcement `announceDeletion(of:)` returned for this file.
    func delete(_ fileUrl: FileUrl?, keepingStoredFile: Bool = false, announced: PendingFileDeletions.Announcement? = nil) {
        guard let fileUrl else {
            announced?.withdraw()
            return
        }
        // Bytes a game peer sent for this file are of no use once the item is gone.
        peerFiles.remove(fileUrl.fileId)
        guard !keepingStoredFile else {
            announced?.withdraw()
            fileBookmarkController.removeBookmark(fileId: fileUrl.fileId)
            return
        }
        // The deletion is findable under the file's path from the moment it was announced, or
        // from here: an import that finds the file unreferenced also finds its deletion and
        // waits for it, instead of reusing a file that is about to go. See CODE_AUDIT_21 §3.6.
        let start: (@escaping @Sendable () async -> Void) -> Void = { deletion in
            if let announced {
                announced.run(deletion)
            } else {
                PendingFileDeletions.shared.start(at: storedLocation(of: fileUrl).map { Self.normalizedPath($0) }, deletion)
            }
        }
        switch fileUrl.location {
            case .local, .appCloud, .newCloud:
                start {
                    await CloudKitOperationCounter.shared.recordOperation(function: "FileUrlDataController.delete(_:)", file: "FileUrlDataController.swift")

                    // The real file, never the temp copy of held peer bytes. See CODE_AUDIT_20 §5.3.
                    guard let accessUrl = await deviceUrl(for: fileUrl, action: { $0 }) else {
                        Logger.fileStore.notice("delete item file: no location resolved for \(fileUrl.rawUrl.lastPathComponent, privacy: .private), file stays")
                        return
                    }
                    // Only drop the bookmark once the file is actually gone (or was
                    // already gone) — a genuine removal failure (coordination
                    // timeout, permission error, transient iCloud state) instead
                    // keeps the bookmark so the file isn't silently orphaned with
                    // nothing left referencing it. See CODE_AUDIT §5.3.
                    guard await removeFileLoggingFailure(at: accessUrl) else { return }
                    Logger.fileStore.notice("delete item file: removed \(accessUrl.lastPathComponent, privacy: .private)")
                    await removeEmptyFolders(above: accessUrl)
                    fileBookmarkController.removeBookmark(fileId: fileUrl.fileId)
                }
            case .url:
                start {
                    let cacheURL = remoteCacheURL(for: fileUrl)
                    guard await removeFileLoggingFailure(at: cacheURL) else { return }
                    fileBookmarkController.removeBookmark(fileId: fileUrl.fileId)
                }
            case .icloud, .other:
                Logger.fileStore.notice("delete item file: \(String(describing: fileUrl.location), privacy: .public) file is not owned by the app, only its bookmark goes")
                announced?.withdraw()
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
        if await removeFileLoggingFailure(at: location) {
            await removeEmptyFolders(above: location)
        }
    }

    /// Where imported bytes for `fileUrl` are written. The sender's relative path is used when
    /// nothing is there, or when the file there already holds exactly these bytes and no item
    /// in `referencedFileUrls` uses it (it is then reused, not rewritten). Otherwise the next
    /// free name in the same folder is taken: imported bytes used to overwrite whatever file
    /// had that name, including another item's file or a newer local version.
    /// See CODE_AUDIT_Folder §5.2.
    func importDestination(for fileUrl: FileUrl, contentHash: String, referencedFileUrls: [FileUrl]) async throws -> FileUrl {
        // A url that names no file is given its own name by `createNewFileUrl`.
        guard fileUrl.location != .url,
              let destination = cloudDocumentController.fullUrl(fileUrl: fileUrl.rawUrl) else { return fileUrl }
        // The file of an item deleted a moment ago is unreferenced and may still be there: its
        // deletion is queued. Reusing it left the imported item without a file once that
        // deletion ran. See CODE_AUDIT_21 §3.6.
        await waitForPendingDeletion(at: destination)
        let (exists, _) = try await FileManager.default.fileExists(coordinatingAccessAt: destination)
        guard exists else { return fileUrl }
        let destinationPath = Self.normalizedPath(destination)
        // By name first, like `isSameStoredFile`. See CODE_AUDIT_21 §7.1.
        let destinationName = destination.lastPathComponent
        let isReferenced = referencedFileUrls.contains { referenced in
            guard let location = storedLocation(of: referenced), location.lastPathComponent == destinationName else { return false }
            return Self.normalizedPath(location) == destinationPath
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
    ///
    /// The file names are compared first: two names are never one file, and that needs no
    /// file-system call. The full comparison resolves symlinks for both paths, and the import
    /// and game-end checks run it for every imported file against every library item.
    /// See CODE_AUDIT_21 §7.1.
    func isSameStoredFile(_ lhs: FileUrl, _ rhs: FileUrl) -> Bool {
        guard let lhsLocation = storedLocation(of: lhs), let rhsLocation = storedLocation(of: rhs),
              lhsLocation.lastPathComponent == rhsLocation.lastPathComponent else { return false }
        return Self.normalizedPath(lhsLocation) == Self.normalizedPath(rhsLocation)
    }

    private static func normalizedPath(_ url: URL) -> String {
        CloudDocumentController.canonicalPath(url)
    }

    /// Waits for a deletion of the stored file at `url` that `delete(_:)` started and that has
    /// not finished. `@concurrent`: the path is resolved on disk. See CODE_AUDIT_21 §3.6.
    @concurrent
    private func waitForPendingDeletion(at url: URL) async {
        await PendingFileDeletions.shared.waitUntilFinished(at: Self.normalizedPath(url))
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
        if await removeFileLoggingFailure(at: fileLocation) {
            await removeEmptyFolders(above: fileLocation)
        }
    }

    /// Removes the file at `url`, logging (rather than silently discarding)
    /// any failure other than the file already being absent. Returns `true`
    /// when the caller may safely treat the file as gone — either it was
    /// actually removed, or it didn't exist in the first place — and `false`
    /// when a real error occurred and the caller should keep whatever
    /// reference (e.g. a bookmark) it was about to drop, so the file isn't
    /// silently orphaned. See CODE_AUDIT §5.3.
    ///
    /// The one place a stored file is removed. It refuses anything that is not a file strictly
    /// below a folder the app stores files in: an imported or mis-resolved path used to be able
    /// to point a delete at a module folder. See CODE_AUDIT_21 §5.1, §6.1.
    internal func removeFileLoggingFailure(at url: URL) async -> Bool {
        guard isBelowFileRoot(url) else {
            Logger.fileStore.fault("Refused to delete \(url.lastPathComponent, privacy: .private): not below a file root of the app")
            return false
        }
        do {
            try await FileManager.default.removeFile(coordinatingAccessAt: url)
            return true
        } catch is DirectoryRemovalRefused {
            Logger.fileStore.fault("Refused to delete \(url.lastPathComponent, privacy: .private): it is a folder")
            return false
        } catch {
            guard (error as NSError).code == NSFileNoSuchFileError else {
                Logger.fileStore.error("Cannot delete file, keeping bookmark for retry \(error.logIdentifier, privacy: .public) \(error.localizedDescription, privacy: .private)")
                return false
            }
            return true
        }
    }

    /// Removes the folders a deleted file left empty, from its own folder upwards, and stops at
    /// the first folder that holds anything else. The module folder itself stays, and so does
    /// anything outside it: only the folders the app made for its files in the module are pruned.
    func removeEmptyFolders(above fileUrl: URL) async {
        let rootPath = Self.normalizedPath(cloudDocumentController.moduleUrl)
        var folder = fileUrl.deletingLastPathComponent()
        while Self.normalizedPath(folder).hasPrefix(rootPath + "/") {
            do {
                guard try await FileManager.default.removeEmptyDirectory(coordinatingAccessAt: folder) else { return }
            } catch {
                Logger.fileStore.error("Cannot remove empty folder \(folder.lastPathComponent, privacy: .private): \(error.logIdentifier, privacy: .public) \(error.localizedDescription, privacy: .private)")
                return
            }
            folder = folder.deletingLastPathComponent()
        }
    }

    /// Whether `url` lies strictly below a folder the app keeps item files in: the module folder,
    /// the legacy app-cloud and local document folders, the remote-file cache or the temporary
    /// folder (staged copies).
    private func isBelowFileRoot(_ url: URL) -> Bool {
        let roots: [URL?] = [
            cloudDocumentController.moduleUrl,
            locationFileManager.rootAppCloud,
            locationFileManager.rootLocal,
            URL.cachesDirectory.appending(path: Self.remoteCacheFolderName, directoryHint: .isDirectory),
            URL.temporaryDirectory
        ]
        let path = Self.normalizedPath(url)
        return roots.contains { root in
            guard let root else { return false }
            let rootPath = Self.normalizedPath(root)
            return path.hasPrefix(rootPath.hasSuffix("/") ? rootPath : rootPath + "/")
        }
    }

    func removeBookmarks(fileId: UUID) {
        fileBookmarkController.removeBookmark(fileId: fileId)
    }

    func download(fileUrl: FileUrl) async throws {
        await CloudKitOperationCounter.shared.recordOperation(function: "FileUrlDataController.download(fileUrl:)", file: "FileUrlDataController.swift")
        
        if fileUrl.location == .newCloud {
            try await cloudDocumentController.download(fileUrl: fileUrl.rawUrl)
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
