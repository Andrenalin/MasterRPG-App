// @copyright André Trettin

import CryptoKit
import SwiftUI
import UniformTypeIdentifiers
import os.log
import Synchronization

// Split out of FileUrlDataController.swift — see CODE_AUDIT_19 §9.23.

// MARK: - Manage files

extension FileUrlDataController {
    /// Moves a `.newCloud` file to `destination`. Returns `nil` when the file is not one this
    /// controller moves; throws when the move fails, so the caller can surface it.
    /// See CODE_AUDIT_Folder §3.8.
    public func move(fileUrl: FileUrl?, to destination: String) async throws -> FileUrl? {
        CloudKitOperationCounter.shared.recordOperation(function: "FileUrlDataController.move(fileUrl:to:)")

        let sourceUrl = fileUrl.flatMap { cloudDocumentController.fullUrl(fileUrl: $0.rawUrl) }
        guard let fileUrl, fileUrl.location == .newCloud, let (fullUrl, relativeUrl) = try await cloudDocumentController.move(url: fileUrl.rawUrl, newName: destination) else { return nil }
        await bookmark(url: fullUrl, fileId: fileUrl.fileId)
        // The folders the file left empty: moving a file out of the last place in a folder
        // used to leave that folder behind on iCloud.
        if let sourceUrl {
            await removeEmptyFolders(above: sourceUrl)
        }

        return FileUrl(fileId: fileUrl.fileId, url: relativeUrl, location: fileUrl.location, module: fileUrl.module, relativeUrl: nil, contentHash: fileUrl.contentHash)
    }

    private func bookmark(url: URL, fileId: UUID) async {
        let securityScope = url.startSecurityScopedAccess()
        defer { securityScope.stop() }
        do {
            try await fileBookmarkController.saveBookmark(fileId: fileId, fileUrl: url)
        } catch {
            Logger.fileStore.error("Cannot create file locally \(error.logIdentifier, privacy: .public) \(error.localizedDescription, privacy: .private)")
        }
    }
}

extension FileUrlDataController {
    func remoteCacheURL(for fileUrl: FileUrl) -> URL {
        let pathExtension = fileUrl.rawUrl.pathExtension.isEmpty
            ? normalizedFilenameExtension
            : fileUrl.rawUrl.pathExtension
        var url = URL.cachesDirectory
            .appending(path: Self.remoteCacheFolderName, directoryHint: .isDirectory)
            .appending(path: locationFileManager.moduleFolder, directoryHint: .isDirectory)
            .appending(path: String(fileUrl.fileId.uuidString.suffix(2)), directoryHint: .isDirectory)
            .appending(path: "\(fileUrl.fileId.uuidString)-\(remoteURLIdentity(for: fileUrl))")
        if !pathExtension.isEmpty {
            url.appendPathExtension(pathExtension)
        }
        return url
    }

    /// The folder below the caches directory that holds the cached copies of `.url` files.
    static let remoteCacheFolderName = "RemoteFiles"

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

    func ensureRemoteCache(for fileUrl: FileUrl) async throws -> URL? {
        guard fileUrl.location == .url,
              fileUrl.rawUrl.isSupportedRemoteFileUrl else {
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

        // One download per cache file, however many readers ask for it at once.
        // See CODE_AUDIT_21 §7.5.
        let remoteUrl = fileUrl.rawUrl
        try await RemoteDownloadsInFlight.shared.run(cachePath: cacheURL.path(percentEncoded: false)) {
            try await downloadIntoRemoteCache(from: remoteUrl, to: cacheURL)
        }
        return cacheURL
    }

    private func downloadIntoRemoteCache(from remoteUrl: URL, to cacheURL: URL) async throws {
        let temporaryUrl = try await remoteFileDownloader(remoteUrl)
        // The download is moved into the cache; whatever is left of it afterwards is removed.
        // It used to be copied and the original stayed in `tmp`, up to 256 MiB per remote item,
        // until the system cleared it. See CODE_AUDIT_21 §7.5.
        defer { try? FileManager.default.removeItem(at: temporaryUrl) }
        try Task.checkCancellation()
        // A remote item may come from a peer; never cache an unbounded download.
        // See CODE_AUDIT_15 §6.3.
        let downloadedSize = (try? temporaryUrl.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard downloadedSize <= Self.maximumRemoteFileBytes else {
            throw URLError(.dataLengthExceedsMaximum)
        }
        try await FileManager.default.createDirectory(
            coordinatingAccessAt: cacheURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        do {
            try await FileManager.default.moveItem(
                coordinatingAccessFrom: temporaryUrl,
                to: cacheURL
            )
        } catch {
            // The cache file can be there already (another process of the app group, an
            // import that restored it); that result is as good.
            guard FileManager.default.fileExists(
                atPath: cacheURL.path(percentEncoded: false)
            ) else {
                throw error
            }
        }
    }

    func cacheRemoteData(
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
    static func downloadRemoteFile(from url: URL) async throws -> URL {
        try await GuardedRemoteDownload.download(from: url, maximumBytes: maximumRemoteFileBytes)
    }

    @MainActor
    static public func empty() -> FileUrlDataController {
        FileUrlDataController(moduleFolder: "Tests", fileTypes: [.image], filenameExtension: "test")
    }
}
