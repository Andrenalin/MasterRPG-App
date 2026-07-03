// @copyright André Trettin

import Combine
import SwiftUI
import UniformTypeIdentifiers
import os.log

extension KeyPath: @unchecked @retroactive Sendable {}

public protocol FileUrlAccessible: Sendable {
    func saveFileUrl(fileUrl: FileUrl) async
}

@MainActor @Observable
public final class FileUrlDataModel {
    var folders: [FileUrlViewModel] = []

    var sortOrder = [KeyPathComparator(\FileUrlViewModel.type, order: .forward), KeyPathComparator(\FileUrlViewModel.name)]

    public var defaultLocation: FileLocation = .newCloud
    public var defaultCloudPath: UUID?

    func append(folder: FileUrlViewModel) {
        folders.append(folder)
        folders.sort(using: sortOrder)
    }

    func resetFolders() {
        folders.removeAll()
    }
}

public struct FileUrlDataController: Sendable {
    private let cloudDocumentController: CloudDocumentController
    private let fileBookmarkController: FileBookmarkController
    private let locationFileManager: LocationFileManager

    public let fileTypes: [UTType]
    let filenameExtension: String
    private let fileUrlAccess: any FileUrlAccessible

    public let model: FileUrlDataModel

    @MainActor
    public init(moduleFolder: String, fileTypes: [UTType], filenameExtension: String, fileUrlAccess: any FileUrlAccessible) {
        let fileBookmarkController = FileBookmarkController(module: moduleFolder)
        self.fileBookmarkController = fileBookmarkController
        self.locationFileManager = LocationFileManager(moduleFolder: moduleFolder)

        self.fileTypes = fileTypes
        self.filenameExtension = filenameExtension
        self.fileUrlAccess = fileUrlAccess

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
        return folders
    }
}

// MARK: - FileUrl Accessors

public extension FileUrlDataController {
    func fileDownloaded(for fileUrl: FileUrl) async -> Bool? {
        guard fileUrl.location != .local && fileUrl.location != .other else { return nil }
        guard await hasAccess(for: fileUrl) else { return nil }
        guard let fullUrl = locationFileManager.absoluteUrl(for: fileUrl.rawUrl, at: fileUrl.location) else { return nil }
        guard let values = try? fullUrl.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]) else { return nil }
        return values.ubiquitousItemDownloadingStatus == .downloaded
    }

    func hasAccess(for fileUrl: FileUrl) async -> Bool {
        let url = await fileBookmarkController.loadBookmark(fileId: fileUrl.fileId)
        var newFileUrl = fileUrl
        if let url, url != locationFileManager.absoluteUrl(for: fileUrl.rawUrl, at: fileUrl.location) {
            Logger.bookmarkStore.info("Different URL detected \(url.absoluteString, privacy: .public)")
            _ = url.startAccessingSecurityScopedResource()
            if let updatedFileUrl = try? await createFileUrl(fileId: fileUrl.fileId, url: url, module: fileUrl.module, category: nil, contentHash: fileUrl.contentHash) {
                await fileUrlAccess.saveFileUrl(fileUrl: updatedFileUrl)
                newFileUrl = updatedFileUrl
            } else {
                Logger.bookmarkStore.info("URL cannot repaired \(fileUrl.rawUrl.absoluteString, privacy: .public)")
            }
            url.stopAccessingSecurityScopedResource()
        }
        guard url != nil || newFileUrl.location == .newCloud || newFileUrl.location == .local || newFileUrl.location == .appCloud else { return false }
        let checkUrl = url ?? newFileUrl.rawUrl
        defer { checkUrl.stopAccessingSecurityScopedResource() }
        return checkUrl.startAccessingSecurityScopedResource()
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
        if fileUrl.location == .newCloud {
            let url = cloudDocumentController.fullUrl(fileUrl: fileUrl.rawUrl)
            return try await action(url)
        }

        let fullUrl = locationFileManager.absoluteUrl(for: fileUrl.rawUrl, at: fileUrl.location) ?? fileUrl.rawUrl
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
        if fileUrl.location == .newCloud {
            let url = cloudDocumentController.fullUrl(fileUrl: fileUrl.rawUrl)
            return try action(url)
        }

        let fullUrl = locationFileManager.absoluteUrl(for: fileUrl.rawUrl, at: fileUrl.location) ?? fileUrl.rawUrl
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
    func createNewFileUrl(fileId: UUID, unconvertedFileUrl: FileUrl, pathExtension: String) async throws -> FileUrl? {
        await CloudKitOperationCounter.shared.recordOperation(function: "FileUrlDataController.createNewFileUrl(fileId:unconvertedFileUrl:pathExtension:)", file: "FileUrlDataController.swift")
        
        guard let oldData = unconvertedFileUrl.data else { return nil }
        let contentHash = unconvertedFileUrl.contentHash ?? FileUrl.contentHash(of: oldData)
        let location: FileLocation = unconvertedFileUrl.location == .url ? .url : .newCloud
        guard let oldUrl = locationFileManager.absoluteUrl(for: unconvertedFileUrl.rawUrl, at: location, module: unconvertedFileUrl.module) else { return nil }

        do {
            // try to get access to the old location (single coordinated check)
            let (exists, isDir) = try await FileManager.default.fileExists(coordinatingAccessAt: oldUrl)
            if exists && !isDir {
                // File already exists on disk - return FileUrl without data in memory
                return FileUrl(fileId: unconvertedFileUrl.fileId, url: unconvertedFileUrl.rawUrl, location: unconvertedFileUrl.location, module: unconvertedFileUrl.module, relativeUrl: nil, contentHash: contentHash)
            }
        } catch {
            Logger.fileStore.error("Different device or different user \(error.localizedDescription, privacy: .public)")
        }

        guard let fileURL = locationFileManager.relativeUrl(for: unconvertedFileUrl.rawUrl) else { return nil }
        let filePath = fileURL.pathComponents.joined(separator: "/")
        let fullUrl: URL = cloudDocumentController.fullUrl(filePath: filePath)

        do {
            // Write uses batched coordination internally now (createDirectory + write)
            try await cloudDocumentController.write(data: oldData, to: filePath)
        } catch {
            Logger.fileStore.error("Cannot create file in cloud app group \(error.localizedDescription, privacy: .public)")
            // Fallback: Keep data in memory when cloud storage fails
            var fileUrl = FileUrl(fileId: fileId, url: fileURL, location: location, module: unconvertedFileUrl.module, relativeUrl: nil)
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
        return FileUrl(fileId: fileId, url: fileURL, location: location, module: unconvertedFileUrl.module, relativeUrl: nil, contentHash: contentHash)
    }

    /// ItemController will call to get FileUrl for given urls from picker
    func createFileUrl(fileId: UUID, url: URL, module: String, category: String?, contentHash: String? = nil) async throws -> FileUrl {
        await CloudKitOperationCounter.shared.recordOperation(function: "FileUrlDataController.createFileUrl(fileId:url:module:category:)", file: "FileUrlDataController.swift")

        do {
            let values = try url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
            if values.ubiquitousItemDownloadingStatus != .current {
                try? FileManager.default.startDownloadingUbiquitousItem(at: url)
            }
        } catch {
            Logger.fileStore.error("Cannot get the download status of url \(url.absoluteString, privacy: .public)")
        }
        let fullUrl = try await cloudDocumentController.createNameUrl(for: url)
        try await fileBookmarkController.saveBookmark(fileId: fileId, fileUrl: fullUrl)
        let nameUrl = cloudDocumentController.nameUrl(fullUrl: fullUrl)
        return FileUrl(fileId: fileId, url: nameUrl, location: .newCloud, module: module, relativeUrl: nil, contentHash: contentHash)
    }

    /// Check if the new URL points to the same file as the existing FileUrl
    func isSameFile(existingFileUrl: FileUrl, newUrl: URL?) async -> Bool {
        guard let newUrl else { return false }

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
            case .icloud, .other, .url:
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
        }
    }

    func duplicate(fileUrl: FileUrl?, for fileId: UUID) async throws -> FileUrl? {
        await CloudKitOperationCounter.shared.recordOperation(function: "FileUrlDataController.duplicate(fileUrl:for:)", file: "FileUrlDataController.swift")
        
        guard var unconverted = fileUrl, let data = try await loadData(for: unconverted) else { return nil }
        unconverted.resetData(data)
        return try await createNewFileUrl(fileId: fileId, unconvertedFileUrl: unconverted, pathExtension: filenameExtension)
    }
}

// MARK: - Manage files

extension FileUrlDataController {
    public func move(fileUrl: FileUrl, name: String, category: String) async throws -> FileUrl? {
        await CloudKitOperationCounter.shared.recordOperation(function: "FileUrlDataController.move(fileUrl:name:category:)", file: "FileUrlDataController.swift")
        
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
    @MainActor
    static public func empty() -> FileUrlDataController {
        FileUrlDataController(moduleFolder: "Tests", fileTypes: [.image], filenameExtension: "test", fileUrlAccess: FakeFileFileAccessible())
    }
}
