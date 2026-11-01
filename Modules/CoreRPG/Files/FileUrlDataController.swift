// @copyright André Trettin

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
    ///
    /// The list is also kept on disk: it used to live in memory only, so a game that ended with
    /// the app being killed left its files behind, and every such session added another
    /// `name-N` copy to iCloud Drive. See CODE_AUDIT_21 §5.14.
    @ObservationIgnored var gameMemoryFiles: [FileUrl] = [] {
        didSet { storeGameMemoryFiles() }
    }

    /// The list a previous run of the app left behind, removed by the launch cleanup.
    @ObservationIgnored private(set) var leftoverGameMemoryFiles: [FileUrl] = []

    @ObservationIgnored private let gameMemoryFilesKey: String?

    /// - Parameter gameMemoryFilesKey: The defaults key the list is kept under, per module.
    ///   `nil` keeps it in memory only.
    init(gameMemoryFilesKey: String? = nil) {
        self.gameMemoryFilesKey = gameMemoryFilesKey
        if let gameMemoryFilesKey,
           let data = UserDefaults.standard.data(forKey: gameMemoryFilesKey),
           let files = try? JSONCoding.decoder.decode([StoredGameMemoryFile].self, from: data) {
            leftoverGameMemoryFiles = files.map(\.fileUrl)
        }
    }

    /// Hands the previous run's list to the launch cleanup and forgets it.
    func takeLeftoverGameMemoryFiles() -> [FileUrl] {
        let files = leftoverGameMemoryFiles
        leftoverGameMemoryFiles = []
        storeGameMemoryFiles()
        return files
    }

    private func storeGameMemoryFiles() {
        guard let gameMemoryFilesKey else { return }
        let files = (leftoverGameMemoryFiles + gameMemoryFiles).map { StoredGameMemoryFile($0) }
        guard !files.isEmpty, let data = try? JSONCoding.encoder.encode(files) else {
            UserDefaults.standard.removeObject(forKey: gameMemoryFilesKey)
            return
        }
        UserDefaults.standard.set(data, forKey: gameMemoryFilesKey)
    }

    /// What is needed to find a stored file again; never the bytes a reference may still hold.
    private struct StoredGameMemoryFile: Codable {
        let fileId: UUID
        let url: URL
        let location: FileLocation
        let module: String

        init(_ fileUrl: FileUrl) {
            fileId = fileUrl.fileId
            url = fileUrl.rawUrl
            location = fileUrl.location
            module = fileUrl.module
        }

        var fileUrl: FileUrl {
            FileUrl(fileId: fileId, url: url, location: location, module: module, relativeUrl: nil)
        }
    }
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

    /// The file controller of a file-backed module, built from its configuration. The four
    /// file-backed item controllers repeated this construction. See CODE_AUDIT_Folder §9.5.
    @MainActor
    public init(config: any ModuleConfigurable) {
        self.init(moduleFolder: config.module.token, fileTypes: config.fileTypes, filenameExtension: config.filenameExtension)
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

        self.model = FileUrlDataModel(gameMemoryFilesKey: "gameMemoryFiles.\(moduleFolder)")

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

// The accessors below are `@concurrent` where they touch the disk: they are plain `async` on a
// `Sendable` struct, so they ran on their caller's actor, which is the main actor for most of
// them. Resource values of an iCloud item, bookmark resolution and security-scoped access are
// IPC that blocks while iCloud is slow. See CODE_AUDIT_21 §3.7.
public extension FileUrlDataController {
    @concurrent
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

    @concurrent
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
    @concurrent
    func hasLocalData(for fileUrl: FileUrl) async -> Bool {
        if fileUrl.hasUnconvertedData { return true }
        if fileUrl.location == .url {
            return FileManager.default.fileExists(
                atPath: remoteCacheURL(for: fileUrl).path(percentEncoded: false)
            )
        }
        let exists = await url(for: fileUrl) { url -> Bool? in
            guard let url else { return false }
            return FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
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
    @concurrent
    func hasDownloadedData(for fileUrl: FileUrl) async -> Bool {
        if fileUrl.hasUnconvertedData { return true }
        if fileUrl.location == .url {
            return await hasLocalData(for: fileUrl)
        }
        let isDownloaded = await deviceUrl(for: fileUrl) { url -> Bool? in
            guard let url, FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return false }
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
    /// `@concurrent`: the first call writes the whole held file, which used to happen on the main
    /// actor when a PDF, 3D model or audio item was opened. See CODE_AUDIT_21 §3.7.
    @concurrent
    private func heldPeerFileUrl(for fileUrl: FileUrl) async -> URL? {
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
        // A read is not counted as a CloudKit operation: browsing a thousand thumbnails would
        // log a false sync-loop warning. See CODE_AUDIT_23 §3.5.
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
        if let heldUrl = await heldPeerFileUrl(for: fileUrl) {
            return try await action(heldUrl)
        }
        return try await deviceUrl(for: fileUrl, action: action)
    }

    func url<T>(for fileUrl: FileUrl, action: @Sendable @escaping (URL?) throws -> T?) async rethrows -> T? {
        if let heldUrl = await heldPeerFileUrl(for: fileUrl) {
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
    ///
    /// `@concurrent`: resolving a bookmark and writing the staged bytes ran on the caller's
    /// (main) actor, a synchronous write of the whole file on every access. The copy is named
    /// after the file id and its content, and an existing one is used as it is.
    /// See CODE_AUDIT_21 §3.7.
    @concurrent
    private func resolveProcessUrl(for fileUrl: FileUrl) async -> ResolvedProcessUrl {
        let fullUrl = locationFileManager.absoluteUrl(
            for: fileUrl.rawUrl,
            at: fileUrl.location,
            module: fileUrl.module
        ) ?? fileUrl.rawUrl
        var loadedFileUrl = await fileBookmarkController.loadBookmark(fileId: fileUrl.fileId)

        if loadedFileUrl == nil, let data = fileUrl.data {
            let tempUrl = stagedCopyUrl(for: fileUrl, data: data)
            // Only take the temp-file path when the write actually succeeded; otherwise fall
            // through and let `loadedFileUrl` stay `nil` so `processUrl` below still falls back
            // to `fullUrl` instead of pointing at a file that was never written. See CODE_AUDIT §5.4.
            if Self.isStagedCopy(at: tempUrl, of: data) || (try? data.write(to: tempUrl, options: .atomic)) != nil {
                loadedFileUrl = tempUrl
            }
        }

        var processUrl = loadedFileUrl ?? fullUrl
        if processUrl.scheme == nil {
            processUrl = fullUrl
        }
        return ResolvedProcessUrl(url: processUrl)
    }

    /// Where the temp copy of staged in-memory bytes goes: one name per file id and content, so
    /// replaced bytes never read an older copy. The hash is the one the reference carries, or
    /// is computed here, off the caller's actor.
    internal func stagedCopyUrl(for fileUrl: FileUrl, data: Data) -> URL {
        let contentHash = fileUrl.contentHash ?? FileUrl.contentHash(of: data)
        // Base64 has `/`, `+` and `=`; only letters and digits go into the file name.
        let token = String(contentHash.filter { $0.isLetter || $0.isNumber }.prefix(24))
        return URL.temporaryDirectory
            .appending(path: "\(fileUrl.fileId.uuidString)-\(token)")
            .appendingPathExtension(filenameExtension)
    }

    /// Whether the temp copy at `url` is already there with all of `data`'s bytes. The copy is
    /// written atomically, so a file of the full size is a complete one.
    private static func isStagedCopy(at url: URL, of data: Data) -> Bool {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return false }
        return size == data.count
    }
}
