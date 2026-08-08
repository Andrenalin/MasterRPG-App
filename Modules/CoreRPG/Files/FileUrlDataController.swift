// @copyright André Trettin

import Combine
import CryptoKit
import SwiftUI
import UniformTypeIdentifiers
import os.log

extension KeyPath: @unchecked @retroactive Sendable {}

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
        return folders.sorted(using: [
            KeyPathComparator(\FileUrlViewModel.type, order: .forward),
            KeyPathComparator(\FileUrlViewModel.name)
        ])
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

    func loadData(for fileUrl: FileUrl) async throws -> Data? {
        await CloudKitOperationCounter.shared.recordOperation(function: "FileUrlDataController.loadData(for:)", file: "FileUrlDataController.swift")
        
        guard !fileUrl.hasUnconvertedData else { return fileUrl.data }
        return try await url(for: fileUrl) { url async throws -> Data? in
            guard let url else { return nil }
            return try await FileManager.default.contentsOfFile(coordinatingAccessAt: url)
        }
    }

    func url<T>(for fileUrl: FileUrl, action: @Sendable @escaping (URL?) async throws -> T?) async rethrows -> T? {
        if fileUrl.location == .url {
            let cachedURL = try? await ensureRemoteCache(for: fileUrl)
            return try await action(cachedURL)
        }

        if fileUrl.location == .newCloud {
            let url = cloudDocumentController.fullUrl(fileUrl: fileUrl.rawUrl)
            return try await action(url)
        }

        let fullUrl = locationFileManager.absoluteUrl(
            for: fileUrl.rawUrl,
            at: fileUrl.location,
            module: fileUrl.module
        ) ?? fileUrl.rawUrl
        let bookmarkedUrl = await fileBookmarkController.loadBookmark(fileId: fileUrl.fileId)

        var processUrl = bookmarkedUrl ?? fullUrl
        if processUrl.scheme == nil {
            processUrl = fullUrl
        }

        defer { processUrl.stopAccessingSecurityScopedResource() }
        _ = processUrl.startAccessingSecurityScopedResource()
        let result = try await action(processUrl)
        return result
    }

    func url<T>(for fileUrl: FileUrl, action: @Sendable @escaping (URL?) throws -> T?) async rethrows -> T? {
        if fileUrl.location == .url {
            let cachedURL = try? await ensureRemoteCache(for: fileUrl)
            return try action(cachedURL)
        }

        if fileUrl.location == .newCloud {
            let url = cloudDocumentController.fullUrl(fileUrl: fileUrl.rawUrl)
            return try action(url)
        }

        let fullUrl = locationFileManager.absoluteUrl(
            for: fileUrl.rawUrl,
            at: fileUrl.location,
            module: fileUrl.module
        ) ?? fileUrl.rawUrl
        var loadedFileUrl = await fileBookmarkController.loadBookmark(fileId: fileUrl.fileId)

        if loadedFileUrl == nil, let data = fileUrl.data {
            let tempUrl = URL.temporaryDirectory.appendingPathComponent(fileUrl.fileId.uuidString).appendingPathExtension(filenameExtension)
            try? data.write(to: tempUrl)
            loadedFileUrl = tempUrl
        }

        var processUrl = loadedFileUrl ?? fullUrl
        if processUrl.scheme == nil {
            processUrl = fullUrl
        }

        defer { processUrl.stopAccessingSecurityScopedResource() }
        _ = processUrl.startAccessingSecurityScopedResource()

        let result = try action(processUrl)
        return result
    }
}

public extension FileUrlDataController {
    /// create a fileUrl with data from an import or on validation / convert data
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
        let _ = fullUrl.startAccessingSecurityScopedResource()
        defer { fullUrl.stopAccessingSecurityScopedResource() }
        do {
            try await fileBookmarkController.saveBookmark(fileId: fileId, fileUrl: fullUrl)
        } catch {
            Logger.fileStore.error("Cannot bookmark file \(error.localizedDescription, privacy: .public)")
        }
        return FileUrl(fileId: fileId, url: fileURL, location: .newCloud, module: unconvertedFileUrl.module, relativeUrl: nil, contentHash: contentHash)
    }

    /// ItemController will call to get FileUrl for given urls from picker
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
                try? FileManager.default.startDownloadingUbiquitousItem(at: url)
            }
        } catch {
            Logger.fileStore.error("Cannot get the download status of url \(url.absoluteString, privacy: .private)")
        }
        let fullUrl = try await cloudDocumentController.createNameUrl(for: url)
        try await fileBookmarkController.saveBookmark(fileId: fileId, fileUrl: fullUrl)
        let nameUrl = cloudDocumentController.nameUrl(fullUrl: fullUrl)
        return FileUrl(fileId: fileId, url: nameUrl, location: .newCloud, module: module, relativeUrl: nil, contentHash: contentHash)
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
                    try? await FileManager.default.removeItem(coordinatingAccessAt: accessUrl)
                    fileBookmarkController.removeBookmark(fileId: fileUrl.fileId)
                }
            case .url:
                Task { @concurrent in
                    let cacheURL = remoteCacheURL(for: fileUrl)
                    try? await FileManager.default.removeItem(coordinatingAccessAt: cacheURL)
                    fileBookmarkController.removeBookmark(fileId: fileUrl.fileId)
                }
            case .icloud, .other:
                fileBookmarkController.removeBookmark(fileId: fileUrl.fileId)
                break
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
        let _ = url.startAccessingSecurityScopedResource()
        defer { url.stopAccessingSecurityScopedResource() }
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

    private func writeRemoteCache(_ data: Data, to cacheURL: URL) async throws {
        try await Task.detached(priority: .utility) {
            try FileManager.default.createDirectory(
                at: cacheURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: cacheURL, options: .atomic)
        }.value
    }

    private static func downloadRemoteFile(from url: URL) async throws -> URL {
        let (temporaryURL, response) = try await URLSession.shared.download(from: url)
        if let response = response as? HTTPURLResponse,
           !(200...299).contains(response.statusCode) {
            throw URLError(.badServerResponse)
        }
        return temporaryURL
    }

    @MainActor
    static public func empty() -> FileUrlDataController {
        FileUrlDataController(moduleFolder: "Tests", fileTypes: [.image], filenameExtension: "test")
    }
}
