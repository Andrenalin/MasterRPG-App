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

    /// Files an import wrote for items that live only in game memory (game deliveries, a loaded
    /// saved game). Removed at game end unless a library item references them by then.
    /// See CODE_AUDIT_Folder §5.26.
    @ObservationIgnored var gameMemoryFiles: [FileUrl] = []
}

public struct FileUrlDataController: Sendable {
    typealias RemoteFileDownloader = @Sendable (URL) async throws -> URL

    let cloudDocumentController: CloudDocumentController
    let fileBookmarkController: FileBookmarkController
    let locationFileManager: LocationFileManager
    let remoteFileDownloader: RemoteFileDownloader
    let peerFiles = PeerFileDataStore.shared

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
            return fileUrl.rawUrl.isSupportedRemoteFileUrl
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

    /// Drops every byte held for game peers. Called when a game ends. See CODE_AUDIT_20 §5.3.
    static func releaseHeldPeerData() {
        PeerFileDataStore.shared.removeAll()
    }

    /// A temporary copy of held peer bytes, for readers that need a file URL (PDF, 3D, audio).
    /// The name carries the store's generation, so a replaced hold can never be shadowed by a
    /// stale temp file, and the bytes and the generation are read together. See CODE_AUDIT_20 §3.8.
    private func heldPeerFileUrl(for fileUrl: FileUrl) -> URL? {
        guard let held = peerFiles.snapshot(for: fileUrl.fileId) else { return nil }
        let pathExtension = fileUrl.rawUrl.pathExtension.isEmpty ? filenameExtension : fileUrl.rawUrl.pathExtension
        let heldUrl = URL.temporaryDirectory
            .appending(path: "peer-\(fileUrl.fileId.uuidString)-\(held.generation)")
            .appendingPathExtension(pathExtension)
        if FileManager.default.fileExists(atPath: heldUrl.path(percentEncoded: false)) { return heldUrl }
        return (try? held.data.write(to: heldUrl, options: .atomic)) == nil ? nil : heldUrl
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
            Logger.fileStore.error("Cannot start the iCloud download of \(url.lastPathComponent, privacy: .private): \(error.logIdentifier, privacy: .public) \(error.localizedDescription, privacy: .private)")
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

    /// The content hash of the file's bytes, never on the caller's actor: a stored file is read
    /// from disk in blocks, bytes held in memory are hashed on the concurrent executor. Loading
    /// a large file whole and hashing it on the main actor cost a full SHA-256 pass there.
    /// See CODE_AUDIT_Folder §7.1.
    func contentHash(for fileUrl: FileUrl) async throws -> String? {
        if let data = fileUrl.data {
            return await FileUrl.computeContentHash(of: data)
        }
        if let held = peerFiles.data(for: fileUrl.fileId) {
            return await FileUrl.computeContentHash(of: held)
        }
        return try await url(for: fileUrl) { url async throws -> String? in
            guard let url else { return nil }
            return try await FileManager.default.contentHash(coordinatingAccessAt: url)
        }
    }

    /// An open handle on the file's bytes, for copying a large file in blocks instead of loading
    /// it whole. Bytes that are only in memory are reached through the same temporary copy
    /// `url(for:action:)` gives every reader. See CODE_AUDIT_Folder §7.1.
    func readHandle(for fileUrl: FileUrl) async throws -> FileHandle? {
        try await url(for: fileUrl) { url async throws -> FileHandle? in
            guard let url else { return nil }
            return try await FileManager.default.fileHandle(coordinatingReadingAt: url)
        }
    }

    func url<T>(for fileUrl: FileUrl, action: @Sendable @escaping (URL?) async throws -> T?) async rethrows -> T? {
        if let heldUrl = heldPeerFileUrl(for: fileUrl) {
            return try await action(heldUrl)
        }
        return try await deviceUrl(for: fileUrl, action: action)
    }

    func url<T>(for fileUrl: FileUrl, action: @Sendable @escaping (URL?) throws -> T?) async rethrows -> T? {
        if let heldUrl = heldPeerFileUrl(for: fileUrl) {
            return try action(heldUrl)
        }
        return try await deviceUrl(for: fileUrl, action: action)
    }

    /// `url(for:action:)` without the held peer copy: where the file really is on this device.
    /// Every mutating operation (delete, move, copy) resolves through this, never the held bytes.
    /// See CODE_AUDIT_20 §5.3.
    func deviceUrl<T>(for fileUrl: FileUrl, action: @Sendable @escaping (URL?) async throws -> T?) async rethrows -> T? {
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

    func deviceUrl<T>(for fileUrl: FileUrl, action: @Sendable @escaping (URL?) throws -> T?) async rethrows -> T? {
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
