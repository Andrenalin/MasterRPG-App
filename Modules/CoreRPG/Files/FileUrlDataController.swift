// @copyright André Trettin

import Combine
import CryptoKit
import SwiftUI
import UniformTypeIdentifiers
import os.log
import Synchronization

@MainActor @Observable
public final class FileUrlDataModel {
    var folders: [FileUrlViewModel] = []
}

public struct FileUrlDataController: Sendable {
    typealias RemoteFileDownloader = @Sendable (URL) async throws -> URL

    private let cloudDocumentController: CloudDocumentController
    private let fileBookmarkController: FileBookmarkController
    private let locationFileManager: LocationFileManager
    private let remoteFileDownloader: RemoteFileDownloader
    private let peerFiles = PeerFileDataStore()

    public let fileTypes: [UTType]
    let filenameExtension: String

    public let model: FileUrlDataModel

    @MainActor
    public init(moduleFolder: String, fileTypes: [UTType], filenameExtension: String) {
        self.init(
            moduleFolder: moduleFolder,
            fileTypes: fileTypes,
            filenameExtension: filenameExtension,
            remoteFileDownloader: Self.downloadRemoteFile(from:)
        )
    }

    @MainActor
    init(
        moduleFolder: String,
        fileTypes: [UTType],
        filenameExtension: String,
        remoteFileDownloader: @escaping RemoteFileDownloader
    ) {
        let fileBookmarkController = FileBookmarkController(module: moduleFolder)
        self.fileBookmarkController = fileBookmarkController
        self.locationFileManager = LocationFileManager(moduleFolder: moduleFolder)
        self.remoteFileDownloader = remoteFileDownloader

        self.fileTypes = fileTypes
        self.filenameExtension = filenameExtension

        self.cloudDocumentController = CloudDocumentController(modulePath: moduleFolder)

        self.model = FileUrlDataModel()

        let saveModel = self.model
        Task {
            let folders = await FileUrlDataController.loadFolderBookmarks(with: fileBookmarkController)
            saveModel.folders = folders
        }
    }

    private static func loadFolderBookmarks(with store: FileBookmarkController) async -> [FileUrlViewModel] {
        let allFolderIds = await store.folders()
        var folders: [FileUrlViewModel] = []
        for id in allFolderIds {
            let url = await store.loadBookmark(fileId: id, folder: true)
            let model = FileUrlViewModel(id: id, name: url?.lastPathComponent ?? "Filename Unknown", path: url?.relativePath ?? "Path not set", type: .folder, hasData: false, hasAccess: true, isDownloaded: nil)
            folders.append(model)
        }
        // A plain comparison instead of `KeyPathComparator`: it needed a global
        // `@unchecked @retroactive Sendable` on `KeyPath`, which weakened every module.
        // See CODE_AUDIT_15 §3.17.
        return folders.sorted { lhs, rhs in
            if lhs.type != rhs.type { return lhs.type < rhs.type }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }
}

// MARK: - FileUrl Accessors

public extension FileUrlDataController {
    func fileDownloaded(for fileUrl: FileUrl) async -> Bool? {
        if fileUrl.location == .url {
            return await hasLocalData(for: fileUrl)
        }
        guard fileUrl.location != .local && fileUrl.location != .other else { return nil }
        guard await hasAccess(for: fileUrl) else { return nil }
        guard let fullUrl = locationFileManager.absoluteUrl(
            for: fileUrl.rawUrl,
            at: fileUrl.location,
            module: fileUrl.module
        ) else { return nil }
        guard let values = try? fullUrl.resourceValues(
            forKeys: [
                .isUbiquitousItemKey,
                .ubiquitousItemDownloadingStatusKey
            ]
        ) else { return nil }
        // `.newCloud` falls back to the shared app-group container when iCloud
        // Drive is unavailable. Those files are already local and have no
        // ubiquitous download status.
        guard values.isUbiquitousItem == true else { return true }
        let status = values.ubiquitousItemDownloadingStatus
        return status == .downloaded || status == .current
    }

    /// Returns whether reading this file can complete without starting an iCloud download.
    /// List thumbnails use this to avoid turning a module switch into a bulk download.
    func isAvailableWithoutDownloading(_ fileUrl: FileUrl) async -> Bool {
        if fileUrl.hasUnconvertedData { return true }
        if peerFiles.data(for: fileUrl.fileId) != nil { return true }

        switch fileUrl.location {
        case .appCloud, .icloud, .newCloud:
            return await fileDownloaded(for: fileUrl) == true
        case .url:
            return await hasLocalData(for: fileUrl)
        case .local, .other:
            return true
        }
    }

    func hasAccess(for fileUrl: FileUrl) async -> Bool {
        let bookmarkedUrl = await fileBookmarkController.loadBookmark(fileId: fileUrl.fileId)
        let managedUrl = locationFileManager.absoluteUrl(
            for: fileUrl.rawUrl,
            at: fileUrl.location,
            module: fileUrl.module
        )
        if let bookmarkedUrl, bookmarkedUrl != managedUrl {
            Logger.bookmarkStore.info("Different URL detected \(bookmarkedUrl.absoluteString, privacy: .private)")
        }

        // Files in containers owned by the app do not require a security-scoped
        // session. `startAccessingSecurityScopedResource()` legitimately returns
        // false for these URLs; treating that as denial caused full-image loading
        // to remove a valid list thumbnail and then refuse to recreate it.
        switch fileUrl.location {
        case .appCloud:
            // Legacy app-cloud metadata can outlive the device's iCloud
            // configuration. It never needs a security-scoped bookmark; actual
            // file availability is checked separately by `hasLocalData(for:)`.
            return true
        case .newCloud, .local:
            return managedUrl != nil
        case .url:
            return fileUrl.rawUrl.isSupportedRemoteFileURL
        case .icloud, .other:
            guard let bookmarkedUrl else { return false }
            let didStartAccess = bookmarkedUrl.startAccessingSecurityScopedResource()
            if didStartAccess {
                bookmarkedUrl.stopAccessingSecurityScopedResource()
            }
            return didStartAccess
        }
    }

    /// Whether the file's binary is available on this device — attached in memory
    /// or present at the resolved local URL. Unlike `hasAccess(for:)` this checks
    /// existence, not permission: an imported item whose binary never arrived has
    /// a valid-looking FileUrl but no local file.
    func hasLocalData(for fileUrl: FileUrl) async -> Bool {
        if fileUrl.hasUnconvertedData { return true }
        if fileUrl.location == .url {
            return FileManager.default.fileExists(
                atPath: remoteCacheURL(for: fileUrl).path(percentEncoded: false)
            )
        }
        let exists = await url(for: fileUrl) { url -> Bool? in
            guard let url else { return false }
            return FileManager.default.fileExists(atPath: url.relativePath)
        }
        return exists ?? false
    }

    /// Whether the file can be read now without waiting for iCloud: like `hasLocalData(for:)`,
    /// but an iCloud Drive item must also be downloaded. A file that has not downloaded yet
    /// still exists on disk as a dataless placeholder (iOS 17, macOS 14), so `hasLocalData`
    /// reports it available — a player then declared a map photo it could not read, discarded
    /// the bytes the master sent, and waited on an iCloud download that can stall. Game-time
    /// checks use this so the bytes come from the peer; it also asks iCloud to fetch the file.
    /// Imports keep `hasLocalData`: an existing placeholder with a matching hash is still the
    /// right file to reuse.
    func hasDownloadedData(for fileUrl: FileUrl) async -> Bool {
        if fileUrl.hasUnconvertedData { return true }
        if fileUrl.location == .url {
            return await hasLocalData(for: fileUrl)
        }
        let isDownloaded = await deviceUrl(for: fileUrl) { url -> Bool? in
            guard let url, FileManager.default.fileExists(atPath: url.relativePath) else { return false }
            return Self.isDownloadedOrLocal(url)
        } ?? false
        if isDownloaded {
            // iCloud delivered the file: the peer's copy is no longer needed.
            peerFiles.remove(fileUrl.fileId)
            return true
        }
        return peerFiles.data(for: fileUrl.fileId) != nil
    }

    /// Keeps the bytes a game peer sent for a file that is on iCloud Drive but not downloaded
    /// on this device, so the game can use them now. The iCloud file itself is never written
    /// (it downloads on its own); the bytes are held here, by file id, not on the item: item
    /// replacement and sync merges compare file references without their bytes and dropped
    /// them, so the player kept requesting the file again. Released once iCloud has the file.
    func holdPeerData(_ data: Data, for fileUrl: FileUrl) {
        peerFiles.hold(data, for: fileUrl.fileId)
    }

    /// A temporary copy of held peer bytes, for readers that need a file URL (PDF, 3D, audio).
    private func heldPeerFileUrl(for fileUrl: FileUrl) -> URL? {
        guard let data = peerFiles.data(for: fileUrl.fileId) else { return nil }
        let pathExtension = fileUrl.rawUrl.pathExtension.isEmpty ? filenameExtension : fileUrl.rawUrl.pathExtension
        let heldUrl = URL.temporaryDirectory
            .appending(path: "peer-\(fileUrl.fileId.uuidString)")
            .appendingPathExtension(pathExtension)
        if FileManager.default.fileExists(atPath: heldUrl.path(percentEncoded: false)) { return heldUrl }
        return (try? data.write(to: heldUrl, options: .atomic)) == nil ? nil : heldUrl
    }

    /// `true` for a file outside iCloud Drive or a downloaded iCloud item. For an iCloud item
    /// that is not downloaded it starts the download and returns `false`.
    private static func isDownloadedOrLocal(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]),
              values.isUbiquitousItem == true else { return true }
        let status = values.ubiquitousItemDownloadingStatus
        if status == .current || status == .downloaded { return true }
        do {
            try FileManager.default.startDownloadingUbiquitousItem(at: url)
        } catch {
            Logger.fileStore.error("Cannot start the iCloud download of \(url.lastPathComponent, privacy: .private): \(error.localizedDescription, privacy: .public)")
        }
        return false
    }

    func loadData(for fileUrl: FileUrl) async throws -> Data? {
        await CloudKitOperationCounter.shared.recordOperation(function: "FileUrlDataController.loadData(for:)", file: "FileUrlDataController.swift")
        
        guard !fileUrl.hasUnconvertedData else { return fileUrl.data }
        if let held = peerFiles.data(for: fileUrl.fileId) { return held }
        return try await url(for: fileUrl) { url async throws -> Data? in
            guard let url else { return nil }
            return try await FileManager.default.contentsOfFile(coordinatingAccessAt: url)
        }
    }

    func url<T>(for fileUrl: FileUrl, action: @Sendable @escaping (URL?) async throws -> T?) async rethrows -> T? {
        if let heldUrl = heldPeerFileUrl(for: fileUrl) {
            return try await action(heldUrl)
        }
        if fileUrl.location == .url {
            let cachedURL = try? await ensureRemoteCache(for: fileUrl)
            return try await action(cachedURL)
        }

        if fileUrl.location == .newCloud {
            let url = cloudDocumentController.fullUrl(fileUrl: fileUrl.rawUrl)
            return try await action(url)
        }

        let resolved = await resolveProcessUrl(for: fileUrl)
        let securityScope = resolved.url.startSecurityScopedAccess()
        defer { securityScope.stop() }
        return try await action(resolved.url)
    }

    func url<T>(for fileUrl: FileUrl, action: @Sendable @escaping (URL?) throws -> T?) async rethrows -> T? {
        if let heldUrl = heldPeerFileUrl(for: fileUrl) {
            return try action(heldUrl)
        }
        return try await deviceUrl(for: fileUrl, action: action)
    }

    /// `url(for:action:)` without the held peer copy: where the file really is on this device.
    private func deviceUrl<T>(for fileUrl: FileUrl, action: @Sendable @escaping (URL?) throws -> T?) async rethrows -> T? {
        if fileUrl.location == .url {
            let cachedURL = try? await ensureRemoteCache(for: fileUrl)
            return try action(cachedURL)
        }

        if fileUrl.location == .newCloud {
            let url = cloudDocumentController.fullUrl(fileUrl: fileUrl.rawUrl)
            return try action(url)
        }

        let resolved = await resolveProcessUrl(for: fileUrl)
        let securityScope = resolved.url.startSecurityScopedAccess()
        defer { securityScope.stop() }
        return try action(resolved.url)
    }

    private struct ResolvedProcessUrl {
        let url: URL
    }

    /// The single resolution used by both `url(for:action:)` overloads, so the sync and async
    /// paths cannot drift: bookmark first, then a private temp copy of staged in-memory bytes,
    /// then the plain file location. The temp copy is written atomically, so concurrent
    /// accesses to one file id never read a half-written file. It is deliberately not deleted
    /// afterwards: callers may hold the URL past the action. See CODE_AUDIT_16 §5.8, §5.10.
    private func resolveProcessUrl(for fileUrl: FileUrl) async -> ResolvedProcessUrl {
        let fullUrl = locationFileManager.absoluteUrl(
            for: fileUrl.rawUrl,
            at: fileUrl.location,
            module: fileUrl.module
        ) ?? fileUrl.rawUrl
        var loadedFileUrl = await fileBookmarkController.loadBookmark(fileId: fileUrl.fileId)

        if loadedFileUrl == nil, let data = fileUrl.data {
            let tempUrl = URL.temporaryDirectory.appending(path: fileUrl.fileId.uuidString).appendingPathExtension(filenameExtension)
            // Only take the temp-file path when the write actually succeeded; otherwise fall
            // through and let `loadedFileUrl` stay `nil` so `processUrl` below still falls back
            // to `fullUrl` instead of pointing at a file that was never written. See CODE_AUDIT §5.4.
            if (try? data.write(to: tempUrl, options: .atomic)) != nil {
                loadedFileUrl = tempUrl
            }
        }

        var processUrl = loadedFileUrl ?? fullUrl
        if processUrl.scheme == nil {
            processUrl = fullUrl
        }
        return ResolvedProcessUrl(url: processUrl)
    }
}

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
                    if let existingData = try? await FileManager.default.contentsOfFile(coordinatingAccessAt: oldUrl),
                       FileUrl.contentHash(of: existingData) == contentHash {
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

    /// ItemController will call to get FileUrl for given urls from picker
    @concurrent
    func createFileUrl(fileId: UUID, url: URL, module: String, category: String?, contentHash: String? = nil) async throws -> FileUrl {
        await CloudKitOperationCounter.shared.recordOperation(function: "FileUrlDataController.createFileUrl(fileId:url:module:category:)", file: "FileUrlDataController.swift")

        if url.isSupportedRemoteFileURL {
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
                let data = try await FileManager.default.contentsOfFile(coordinatingAccessAt: url)
                resolvedContentHash = FileUrl.contentHash(of: data)
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
        if existingFileUrl.location == .url || newUrl.isSupportedRemoteFileURL {
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

// MARK: - Manage files

extension FileUrlDataController {
    public func move(fileUrl: FileUrl, name: String, category: String) async throws -> FileUrl? {
        await CloudKitOperationCounter.shared.recordOperation(function: "FileUrlDataController.move(fileUrl:name:category:)", file: "FileUrlDataController.swift")

        if fileUrl.location == .url {
            return fileUrl
        }
        
        return try await url(for: fileUrl) { url -> FileUrl? in
            guard let url else { return nil }
            var part = (locationFileManager.relativeUrl(for: fileUrl.rawUrl) ?? fileUrl.rawUrl).absoluteString
            if fileUrl.location == .icloud {
                let folders = await fileBookmarkController.folders()
                for folderId in folders {
                    guard let folderUrl = await self.fileBookmarkController.loadBookmark(fileId: folderId, folder: true) else { continue }
                    if url.absoluteString.hasPrefix(folderUrl.absoluteString) {
                        let count = folderUrl.pathComponents.count
                        let filePath = url.pathComponents.dropFirst(count)
                        part = filePath.joined(separator: "/")
                        break
                    }
                }
            } else {
                if let suggestedName = try? await cloudDocumentController.suggestedFileName(for: category, filename: name) {
                    part = category + "/" + suggestedName
                }
            }

            let destinationName = try await cloudDocumentController.move(sourceUrl: url, destinationFilename: part)
            guard let newUrl = URL(string: destinationName) else { return nil }
            if fileUrl.location == .local || fileUrl.location == .appCloud {
                try? await FileManager.default.removeItem(coordinatingAccessAt: url)
            }
            let newFileUrl = FileUrl(fileId: fileUrl.fileId, url: newUrl, location: .newCloud, module: fileUrl.module, relativeUrl: nil, contentHash: fileUrl.contentHash)
            return newFileUrl
        }
    }

    public func move(fileUrl: FileUrl?, from source: ItemListCategory, to destination: ItemListCategory) async -> FileUrl? {
        await CloudKitOperationCounter.shared.recordOperation(function: "FileUrlDataController.move(fileUrl:from:to:)", file: "FileUrlDataController.swift")
        
        do {
            guard let fileUrl, fileUrl.location == .newCloud else { return nil }
            let components = fileUrl.rawUrl.pathComponents
            let firstComponent = components.first ?? ""
            let secondComponent = components.count > 1 ? components[1] : ""
            guard firstComponent == source.title || secondComponent == source.title, let (fullUrl, relativeUrl) = try await cloudDocumentController.move(url: fileUrl.rawUrl, newCategory: destination.title) else { return nil }
            await bookmark(url: fullUrl, fileId: fileUrl.fileId)

            return FileUrl(fileId: fileUrl.fileId, url: relativeUrl, location: fileUrl.location, module: fileUrl.module, relativeUrl: nil, contentHash: fileUrl.contentHash)
        } catch {
            Logger.fileStore.error("Error moving file \(error.localizedDescription, privacy: .public)")
        }
        return nil
    }

    public func move(fileUrl: FileUrl?, to destination: String) async -> FileUrl? {
        await CloudKitOperationCounter.shared.recordOperation(function: "FileUrlDataController.move(fileUrl:to:)", file: "FileUrlDataController.swift")
        
        do {
            guard let fileUrl, fileUrl.location == .newCloud, let (fullUrl, relativeUrl) = try await cloudDocumentController.move(url: fileUrl.rawUrl, newName: destination) else { return nil }
            await bookmark(url: fullUrl, fileId: fileUrl.fileId)

            return FileUrl(fileId: fileUrl.fileId, url: relativeUrl, location: fileUrl.location, module: fileUrl.module, relativeUrl: nil, contentHash: fileUrl.contentHash)
        } catch {
            Logger.fileStore.error("Error moving file \(error.localizedDescription, privacy: .public)")
        }
        return nil
    }

    private func bookmark(url: URL, fileId: UUID) async {
        let securityScope = url.startSecurityScopedAccess()
        defer { securityScope.stop() }
        do {
            try await fileBookmarkController.saveBookmark(fileId: fileId, fileUrl: url)
        } catch {
            Logger.fileStore.error("Cannot create file locally \(error.localizedDescription, privacy: .public)")
        }
    }
}

extension FileUrlDataController {
    func remoteCacheURL(for fileUrl: FileUrl) -> URL {
        let pathExtension = fileUrl.rawUrl.pathExtension.isEmpty
            ? normalizedFilenameExtension
            : fileUrl.rawUrl.pathExtension
        var url = URL.cachesDirectory
            .appending(path: "RemoteFiles", directoryHint: .isDirectory)
            .appending(path: locationFileManager.moduleFolder, directoryHint: .isDirectory)
            .appending(path: String(fileUrl.fileId.uuidString.suffix(2)), directoryHint: .isDirectory)
            .appending(path: "\(fileUrl.fileId.uuidString)-\(remoteURLIdentity(for: fileUrl))")
        if !pathExtension.isEmpty {
            url.appendPathExtension(pathExtension)
        }
        return url
    }

    private func remoteURLIdentity(for fileUrl: FileUrl) -> String {
        Data(SHA256.hash(data: Data(fileUrl.rawUrl.absoluteString.utf8)))
            .base64EncodedString()
            .replacing("/", with: "_")
            .replacing("+", with: "-")
            .replacing("=", with: "")
    }

    private var normalizedFilenameExtension: String {
        filenameExtension.first == "."
            ? String(filenameExtension.dropFirst())
            : filenameExtension
    }

    /// Largest remote file the device caches on behalf of a `.url` item.
    private static let maximumRemoteFileBytes = ByteLimits.maximumSourceFileBytes

    private func ensureRemoteCache(for fileUrl: FileUrl) async throws -> URL? {
        guard fileUrl.location == .url,
              fileUrl.rawUrl.isSupportedRemoteFileURL else {
            return nil
        }

        let cacheURL = remoteCacheURL(for: fileUrl)
        if FileManager.default.fileExists(atPath: cacheURL.path(percentEncoded: false)) {
            return cacheURL
        }

        if let data = fileUrl.data {
            try await writeRemoteCache(data, to: cacheURL)
            return cacheURL
        }

        let temporaryURL = try await remoteFileDownloader(fileUrl.rawUrl)
        try Task.checkCancellation()
        // A remote item may come from a peer; never cache an unbounded download.
        // See CODE_AUDIT_15 §6.3.
        let downloadedSize = (try? temporaryURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard downloadedSize <= Self.maximumRemoteFileBytes else {
            try? FileManager.default.removeItem(at: temporaryURL)
            throw URLError(.dataLengthExceedsMaximum)
        }
        try await FileManager.default.createDirectory(
            coordinatingAccessAt: cacheURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        do {
            try await FileManager.default.copyItem(
                coordinatingAccessFrom: temporaryURL,
                to: cacheURL
            )
        } catch {
            // Multiple consumers can request the same uncached file together. The
            // first completed copy wins; later copies may safely reuse that result.
            guard FileManager.default.fileExists(
                atPath: cacheURL.path(percentEncoded: false)
            ) else {
                throw error
            }
        }
        return cacheURL
    }

    private func cacheRemoteData(
        _ data: Data,
        fileId: UUID,
        source: FileUrl
    ) async throws -> FileUrl {
        var cachedFileURL = FileUrl(
            fileId: fileId,
            url: source.rawUrl,
            location: .url,
            module: source.module,
            relativeUrl: nil,
            contentHash: source.contentHash
        )
        cachedFileURL.resetContentHash(of: data)
        try await writeRemoteCache(data, to: remoteCacheURL(for: cachedFileURL))
        return cachedFileURL
    }

    /// Off the caller's executor and structured. See CODE_AUDIT_18 §4.4.
    @concurrent
    private func writeRemoteCache(_ data: Data, to cacheURL: URL) async throws {
        try Task.checkCancellation()
        try FileManager.default.createDirectory(
            at: cacheURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: cacheURL, options: .atomic)
    }

    /// Redirects to non-public hosts are refused and the size cap is enforced during the
    /// transfer. See CODE_AUDIT_18 §6.5.
    private static func downloadRemoteFile(from url: URL) async throws -> URL {
        try await GuardedRemoteDownload.download(from: url, maximumBytes: maximumRemoteFileBytes)
    }

    @MainActor
    static public func empty() -> FileUrlDataController {
        FileUrlDataController(moduleFolder: "Tests", fileTypes: [.image], filenameExtension: "test")
    }
}

/// Bytes game peers sent for files not downloaded from iCloud on this device, by file id.
/// Shared by the copies of one module's `FileUrlDataController`.
final class PeerFileDataStore: Sendable {
    private let entries = Mutex<[UUID: Data]>([:])

    func data(for fileId: UUID) -> Data? {
        entries.withLock { $0[fileId] }
    }

    func hold(_ data: Data, for fileId: UUID) {
        let replaced = entries.withLock { entries -> Bool in
            defer { entries[fileId] = data }
            return entries[fileId] != nil && entries[fileId] != data
        }
        if replaced { Self.removeTemporaryCopy(of: fileId) }
    }

    func remove(_ fileId: UUID) {
        let removed = entries.withLock { $0.removeValue(forKey: fileId) != nil }
        if removed { Self.removeTemporaryCopy(of: fileId) }
    }

    private static func removeTemporaryCopy(of fileId: UUID) {
        let prefix = "peer-\(fileId.uuidString)"
        let directory = URL.temporaryDirectory
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false)) else { return }
        for name in names where name.hasPrefix(prefix) {
            try? FileManager.default.removeItem(at: directory.appending(path: name))
        }
    }
}
