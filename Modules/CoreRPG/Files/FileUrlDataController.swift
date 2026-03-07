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
public final class FileUrlDataModel: Sendable {
    var folders: [FileUrlViewModel] = []

    var sortOrder = [KeyPathComparator(\FileUrlViewModel.type, order: .forward), KeyPathComparator(\FileUrlViewModel.name)]

    public var defaultLoaction: FileLocation = .newCloud
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
            defer { url.stopAccessingSecurityScopedResource() }
            if let updatedFileUrl = try? await createFileUrl(fileId: fileUrl.fileId, url: url, module: fileUrl.module, category: nil) {
                let saveTask = Task { @MainActor in                    
                    await fileUrlAccess.saveFileUrl(fileUrl: updatedFileUrl)
                }
                let _ = await saveTask.result
                newFileUrl = updatedFileUrl
            } else {
                Logger.bookmarkStore.info("URL cannot repaired \(fileUrl.rawUrl.absoluteString, privacy: .public)")
            }
        }
        guard url != nil || newFileUrl.location == .newCloud || newFileUrl.location == .local || newFileUrl.location == .appCloud else { return false }
        let checkUrl = url ?? newFileUrl.rawUrl
        defer { checkUrl.stopAccessingSecurityScopedResource() }
        return checkUrl.startAccessingSecurityScopedResource()
    }

    func loadData(for fileUrl: FileUrl) async throws -> Data? {
        guard !fileUrl.hasUnconvertedData else { return fileUrl.data }
        return try await url(for: fileUrl) { url async throws -> Data? in
            guard let url else { return nil }
            return try await FileManager.default.contentsOfFile(coordinatingAccessAt: url)
        }
    }

    func url<T>(for fileUrl: FileUrl, action: @escaping (URL?) async throws -> T?) async rethrows -> T? {
        if fileUrl.location == .newCloud {
            let url = cloudDocumentController.fullUrl(fileUrl: fileUrl.rawUrl)
            return try await action(url)
        }

        let fullUrl = locationFileManager.absoluteUrl(for: fileUrl.rawUrl, at: fileUrl.location) ?? fileUrl.rawUrl
        let fileUrl = await fileBookmarkController.loadBookmark(fileId: fileUrl.fileId)

        var processUrl = fileUrl ?? fullUrl
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
        guard let oldData = unconvertedFileUrl.data else { return nil }
        let location: FileLocation = unconvertedFileUrl.location == .url ? .url : .newCloud
        guard let oldUrl = locationFileManager.absoluteUrl(for: unconvertedFileUrl.rawUrl, at: location, module: unconvertedFileUrl.module) else { return nil }

        do {
            // try to get access to the old location
            let (exists, isDir) = try await FileManager.default.fileExists(coordinatingAccessAt: oldUrl)
            if exists && !isDir {
                return unconvertedFileUrl
            }
        } catch {
            Logger.fileStore.error("Different device or different user \(error.localizedDescription, privacy: .public)")
        }


        guard let fileURL = locationFileManager.relativeUrl(for: unconvertedFileUrl.rawUrl) else { return nil }
        let filePath = fileURL.pathComponents.joined(separator: "/")
        let fullUrl: URL = cloudDocumentController.fullUrl(filePath: filePath)
        do {
            try await cloudDocumentController.write(data: oldData, to: filePath)
        } catch {
            Logger.fileStore.error("Cannot create file in cloud app group \(error.localizedDescription, privacy: .public)")
            let fullUrl = try? await locationFileManager.createLocalUrl(id: fileId, pathExtension: pathExtension)
            var fileUrl = FileUrl(fileId: fileId, url: fullUrl ?? URL(fileURLWithPath: ""), location: .local, module: unconvertedFileUrl.module, relativeUrl: locationFileManager.relativeUrl(for: fullUrl))
            fileUrl.resetData(oldData) // added if any platform has issue to save data.
            return fileUrl
        }
        let _ = fullUrl.startAccessingSecurityScopedResource()
        defer { fullUrl.stopAccessingSecurityScopedResource() }
        do {
            try await fileBookmarkController.saveBookmark(fileId: fileId, fileUrl: fullUrl)
        } catch {
            Logger.fileStore.error("Cannot bookmark file \(error.localizedDescription, privacy: .public)")
        }
        var fileUrl = FileUrl(fileId: fileId, url: fileURL, location: location, module: unconvertedFileUrl.module, relativeUrl: nil)
        fileUrl.resetData(oldData) // added if any platform has issue to save data.
        return fileUrl
    }

    /// ItemController will call to get FileUrl for given urls from picker
    func createFileUrl(fileId: UUID, url: URL, module: String, category: String?) async throws -> FileUrl {
        do {
            let values = try url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
            if values.ubiquitousItemDownloadingStatus != .current {
                try? FileManager.default.startDownloadingUbiquitousItem(at: url)
            }
        } catch {
            Logger.fileStore.error("Cannot get the download status of url \(url.absoluteString, privacy: .public)")
        }
        let fullUrl = try await cloudDocumentController.createNameUrl(for: url, category: category ?? "New".localizedString)
        try await fileBookmarkController.saveBookmark(fileId: fileId, fileUrl: fullUrl)
        let nameUrl = cloudDocumentController.nameUrl(fullUrl: fullUrl)
        return FileUrl(fileId: fileId, url: nameUrl, location: .newCloud, module: module, relativeUrl: nil)
    }

    /// called from ItemStore on delete of the item
    func delete(_ fileUrl: FileUrl?) {
        guard let fileUrl else { return }
        switch fileUrl.location {
            case .local, .appCloud, .newCloud:
                Task {
                    guard let accessUrl = await url(for: fileUrl, action: { $0 }) else { return }
                    // ignore any exception. If the file cannot be remove we cannot recover
                    try await FileManager.default.removeItem(coordinatingAccessAt: accessUrl)
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
        if fileUrl.location == .newCloud {
            try await cloudDocumentController.download(filePath: fileUrl.rawUrl.absoluteString)
        }
    }

    func duplicate(fileUrl: FileUrl?, for fileId: UUID) async throws -> FileUrl? {
        guard var unconverted = fileUrl, let data = try await loadData(for: unconverted) else { return nil }
        unconverted.resetData(data)
        return try await createNewFileUrl(fileId: fileId, unconvertedFileUrl: unconverted, pathExtension: filenameExtension)
    }
}

// MARK: - Manage files

extension FileUrlDataController {
    public func move(fileUrl: FileUrl, name: String, category: String) async throws -> FileUrl? {
        try await url(for: fileUrl) { url -> FileUrl? in
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
            let newFileUrl = FileUrl(fileId: fileUrl.fileId, url: newUrl, location: .newCloud, module: fileUrl.module, relativeUrl: nil)
            return newFileUrl
        }
    }

    public func move(fileUrl: FileUrl?, from source: ItemListCategory, to destination: ItemListCategory) async -> FileUrl? {
        do {
            guard let fileUrl, fileUrl.location == .newCloud else { return nil }
            let components = fileUrl.rawUrl.pathComponents
            let firstComponent = components.first ?? ""
            let secondComponent = components.count > 1 ? components[1] : ""
            guard firstComponent == source.title || secondComponent == source.title, let (fullUrl, relativeUrl) = try await cloudDocumentController.move(url: fileUrl.rawUrl, newCategory: destination.title) else { return nil }
            await bookmark(url: fullUrl, fileId: fileUrl.fileId)

            return FileUrl(fileId: fileUrl.fileId, url: relativeUrl, location: fileUrl.location, module: fileUrl.module, relativeUrl: nil)
        } catch {
            Logger.fileStore.error("Error moving file \(error.localizedDescription, privacy: .public)")
        }
        return nil
    }

    public func move(fileUrl: FileUrl?, to destination: String) async -> FileUrl? {
        do {
            guard let fileUrl, fileUrl.location == .newCloud, let (fullUrl, relativeUrl) = try await cloudDocumentController.move(url: fileUrl.rawUrl, newName: destination) else { return nil }
            await bookmark(url: fullUrl, fileId: fileUrl.fileId)

            return FileUrl(fileId: fileUrl.fileId, url: relativeUrl, location: fileUrl.location, module: fileUrl.module, relativeUrl: nil)
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
