// @copyright André Trettin

import Combine
import CryptoKit
import SwiftUI
import UniformTypeIdentifiers
import os.log
import Synchronization

// Split out of FileUrlDataController.swift — see CODE_AUDIT_19 §9.23.

// MARK: - Manage files

extension FileUrlDataController {
    public func move(fileUrl: FileUrl, name: String, category: String) async throws -> FileUrl? {
        await CloudKitOperationCounter.shared.recordOperation(function: "FileUrlDataController.move(fileUrl:name:category:)", file: "FileUrlDataController.swift")

        if fileUrl.location == .url {
            return fileUrl
        }
        
        // The real file, never the temp copy of held peer bytes: moving that copy into Documents
        // left the original behind. See CODE_AUDIT_20 §5.3.
        return try await deviceUrl(for: fileUrl) { url -> FileUrl? in
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

        let temporaryUrl = try await remoteFileDownloader(fileUrl.rawUrl)
        try Task.checkCancellation()
        // A remote item may come from a peer; never cache an unbounded download.
        // See CODE_AUDIT_15 §6.3.
        let downloadedSize = (try? temporaryUrl.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard downloadedSize <= Self.maximumRemoteFileBytes else {
            try? FileManager.default.removeItem(at: temporaryUrl)
            throw URLError(.dataLengthExceedsMaximum)
        }
        try await FileManager.default.createDirectory(
            coordinatingAccessAt: cacheURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        do {
            try await FileManager.default.copyItem(
                coordinatingAccessFrom: temporaryUrl,
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
