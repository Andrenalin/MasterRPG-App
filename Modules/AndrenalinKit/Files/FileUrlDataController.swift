// @copyright André Trettin

import Combine
import SwiftUI
import UniformTypeIdentifiers
import os.log

extension KeyPath: @unchecked @retroactive Sendable {}

public protocol FileUrlAccessible: Sendable {
    func fetchFileUrl() async -> [FileUrl]
    func saveFileUrl(fileUrl: FileUrl) async
    
    func fileUrl(item: any Observable) async -> FileUrl?
    func setFileUrl(_ fileUrl: FileUrl?, item: any Observable) async
}

@MainActor @Observable
public final class FileUrlDataModel: Sendable {
    var fileUrls: [FileUrlViewModel] = []
    var folders: [FileUrlViewModel] = []
    var processing: Int = 0

    var sortOrder = [KeyPathComparator(\FileUrlViewModel.type, order: .forward), KeyPathComparator(\FileUrlViewModel.name)]

    public var defaultLoaction: FileLocation = .appCloud
    public var defaultCloudPath: UUID?
    
    func append(folder: FileUrlViewModel) {
        folders.append(folder)
        folders.sort(using: sortOrder)
    }
    
    func resetFolders() {
        folders.removeAll()
    }
    
    func increaseProcessing() {
        processing += 1
    }
    
    func decreaseProcessing() {
        processing -= 1
    }
}

public struct FileUrlDataController: Sendable {
    private let fileBookmarkController: FileBookmarkController
    private let locationFileManager: LocationFileManager
    
    let fileTypes: [UTType]
    let filenameExtension: String
    private let fileUrlAccess: any FileUrlAccessible

    private let cloudDocumentController: CloudDocumentController
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
    
    @MainActor
    var fileUrls: [FileUrlViewModel] {
        get { model.fileUrls }
        nonmutating set { model.fileUrls = newValue }
    }
    
    @MainActor
    var folders: [FileUrlViewModel] {
        get { model.folders }
        nonmutating set { model.folders = newValue }
    }
    
    @MainActor
    var processing: Int {
        get { model.processing }
        nonmutating set { model.processing = newValue }
    }

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
                let suggestedName = try? await cloudDocumentController.suggestedFileName(for: category, filename: name)
                part = suggestedName ?? part
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
}

// MARK: - Init Setup

private extension FileUrlDataController {
    static func loadFolderBookmarks(with store: FileBookmarkController) async -> [FileUrlViewModel] {
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

// MARK: - Folder

public extension FileUrlDataController {
    func addFolder(url: URL) async throws {
        let folderId = UUID()
        try await fileBookmarkController.saveBookmark(fileId: folderId, fileUrl: url, folder: true)
        
        let model = FileUrlViewModel(id: folderId, name: url.lastPathComponent, path: url.relativePath, type: .folder, hasData: false, hasAccess: true, isDownloaded: nil)
        await self.model.append(folder: model)
    }
    
    func removeFolder(id: UUID) async {
        fileBookmarkController.removeBookmark(fileId: id)
        await model.resetFolders()
    }
}

// MARK: - FileUrl Accessors

public extension FileUrlDataController {
    func absoluteFileName(for fileUrl: FileUrl) -> String {
        let fullUrl = locationFileManager.absoluteUrl(for: fileUrl.rawUrl, at: fileUrl.location) ?? fileUrl.rawUrl
        return fullUrl.absoluteString
    }

    func canRead(for fileUrl: FileUrl) async -> Bool {
        if await hasAccess(for: fileUrl) {
            return (await url(for: fileUrl) { url in
                guard let url else { return false }
                let data = try? Data(contentsOf: url)
                return data != nil
            } ?? false)
        }
        return false
    }

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
    func change(fileUrl: FileUrl, to newLocation: FileLocation, newUrl: URL? = nil) async throws -> FileUrl? {
        guard let accessUrl = await url(for: fileUrl, action: { $0 }) else { return nil }

        let destUrl: URL?
        if newLocation == .other || newLocation == .icloud {
            guard let newUrl else { return nil }
            let folderUrl = newUrl.deletingLastPathComponent()
            let (exists, _) = try await FileManager.default.fileExists(coordinatingAccessAt: folderUrl)
            if !exists {
                try await FileManager.default.createDirectory(coordinatingAccessAt: folderUrl, withIntermediateDirectories: true)
            }
            destUrl = try await locationFileManager.copy(pickedURL: accessUrl, to: newUrl)
        } else {
            destUrl = try await locationFileManager.copy(pickedURL: accessUrl, to: newLocation, id: fileUrl.fileId)
        }
        guard let destUrl else { return nil }
        fileBookmarkController.removeBookmark(fileId: fileUrl.fileId)
        if fileUrl.location == .local || fileUrl.location == .appCloud {
            try await locationFileManager.remove(url: accessUrl)
        }
        try await fileBookmarkController.saveBookmark(fileId: fileUrl.fileId, fileUrl: destUrl)
        return FileUrl(fileId: fileUrl.fileId, url: destUrl, location: newLocation, module: fileUrl.module, relativeUrl: locationFileManager.relativeUrl(for: destUrl))
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
    
    func download(fileUrl: FileUrl) async throws {
        if fileUrl.location == .newCloud {
            try await cloudDocumentController.download(filePath: fileUrl.rawUrl.absoluteString)
        } else {
            _ = await validateFiles(fileUrls: [fileUrl])
        }
    }

    func duplicate(fileUrl: FileUrl?, for fileId: UUID) async throws -> FileUrl? {
        guard let unconverted = fileUrl, let data = try await loadData(for: unconverted) else { return nil }
        var fullURL: URL? = nil
        switch unconverted.location {
        case .appCloud, .local:
            fullURL = try await locationFileManager.create(id: fileId, location: unconverted.location, pathExtension: filenameExtension, data: data)
            break
            case .other, .icloud, .newCloud:
            // try to get access to the old location
            let oldUrl = locationFileManager.absoluteUrl(for: unconverted.rawUrl, at: unconverted.location) ?? unconverted.rawUrl
            let (exists, isDir) = try await FileManager.default.fileExists(coordinatingAccessAt: oldUrl)
            let hasAccess = await hasAccess(for: unconverted)
            if exists && !isDir && (unconverted.location != .other || hasAccess) {
                let newUrl = await fileBookmarkController.loadBookmark(fileId: unconverted.fileId)
                fullURL = newUrl
            }
            break
            case .url:
                fullURL = unconverted.rawUrl
            break
        }
        guard let fullURL else { return nil }
        do {
            defer { fullURL.stopAccessingSecurityScopedResource() }
            _ = fullURL.startAccessingSecurityScopedResource()
            try await fileBookmarkController.saveBookmark(fileId: fileId, fileUrl: fullURL)
            return FileUrl(fileId: fileId, url: fullURL, location: locationFileManager.fileLocation(for: fullURL), module: unconverted.module, relativeUrl: locationFileManager.relativeUrl(for: fullURL))
        } catch {
            print(error.localizedDescription)
        }
        return nil
    }

    func fetch() async {
        var fileModels: [FileUrlViewModel] = []
        for fileUrl in await fileUrlAccess.fetchFileUrl() {
            let model = FileUrlViewModel(id: fileUrl.fileId, name: fileUrl.rawUrl.lastPathComponent, path: fileUrl.rawUrl.relativePath, type: .file, hasData: fileUrl.data != nil, hasAccess: await hasAccess(for: fileUrl), isDownloaded: await fileDownloaded(for: fileUrl), fileUrl: fileUrl)
            fileModels.append(model)
        }
        let models = fileModels
        let setTask = Task { @MainActor in
            fileUrls = models.sorted(using: model.sortOrder)
        }
        let _ = await setTask.result
    }
}

// MARK: Convert

extension FileUrlDataController {
    public func convertFileDataValidate() async {
        await fetch()
        let convertTask = Task.detached(priority: .utility) {
            await self.convertData()
            _ = await self.validateFiles()
        }
        let _ = await convertTask.result
    }

    public func convertData() async {
        let all = await fileUrls.filter { $0.hasData && $0.fileUrl != nil }
        for fileViewModel in all {
            await convertData(fileId: fileViewModel.id)
        }
    }

    func convertData(fileId: UUID) async {
        guard let index = await fileUrls.firstIndex(where: { $0.id == fileId }) else { return }
        await model.increaseProcessing()
        if let fileUrl = await fileUrls[index].fileUrl {
            _ = await validateFiles(fileUrls: [fileUrl])
        }
        if let fileUrl = await convertFileUrl(fileUrl: fileUrls[index].fileUrl) {
            await fileUrlAccess.saveFileUrl(fileUrl: fileUrl)
        }
        await model.decreaseProcessing()
    }

    private func convertFileUrl(fileUrl: FileUrl?) async -> FileUrl? {
        guard let fileUrl else { return nil }
        do {
            var pathExtension = fileUrl.rawUrl.pathExtension
            if pathExtension.isEmpty {
                switch fileUrl.module {
                case NetworkModules.audio.token:
                    pathExtension = "mp4"
                case NetworkModules.photo.token:
                    pathExtension = "jpg"
                case NetworkModules.pdf.token:
                    pathExtension = "pdf"
                default:
                    break
                }
            }
            return try await createFileUrl(fileId: fileUrl.fileId, unconvertedFileUrl: fileUrl, pathExtension: pathExtension)
        } catch {
            print(error.localizedDescription)
        }
        return nil
    }

    /// create a fileUrl with data from an import or on validation / convert data
    func createFileUrl(fileId: UUID, unconvertedFileUrl: FileUrl, pathExtension: String) async throws -> FileUrl? {
        guard let oldData = unconvertedFileUrl.data else { return nil }
        var location = unconvertedFileUrl.location
        var fullURL: URL? = nil
        let oldName = unconvertedFileUrl.rawUrl.lastPathComponent

        do {
            // try to get access to the old location
            let oldUrl = locationFileManager.absoluteUrl(for: unconvertedFileUrl.rawUrl, at: location) ?? unconvertedFileUrl.rawUrl
            let (exists, isDir) = try await FileManager.default.fileExists(coordinatingAccessAt: oldUrl)
            let hasAccess = await hasAccess(for: unconvertedFileUrl)
            if exists && !isDir && (location != .other || hasAccess) {
                if let newUrl = await fileBookmarkController.loadBookmark(fileId: unconvertedFileUrl.fileId) {
                    location = locationFileManager.fileLocation(for: newUrl) ?? unconvertedFileUrl.location
                    fullURL = newUrl
                } else if location != .local {
                    return unconvertedFileUrl
                }
            } else if location == .icloud {
                if await validateFiles(fileUrls: [unconvertedFileUrl]), let newUrl = await fileBookmarkController.loadBookmark(fileId: unconvertedFileUrl.fileId) {
                    location = locationFileManager.fileLocation(for: newUrl) ?? unconvertedFileUrl.location
                    fullURL = newUrl
                }
            }
        } catch {
            Logger.fileStore.error("Different device or different user \(error.localizedDescription, privacy: .public)")
        }

        if fullURL == nil {
            location = await model.defaultLoaction
            if location == .icloud {
                if let defaultCloudPath = await model.defaultCloudPath, let cloudUrl = await self.fileBookmarkController.loadBookmark(fileId: defaultCloudPath, folder: true), cloudUrl.startAccessingSecurityScopedResource() {
                    defer { cloudUrl.stopAccessingSecurityScopedResource() }

                    let cloudFileUrl = cloudUrl.appendingPathComponent(oldName)
                    let (exists, isDir) = try await FileManager.default.fileExists(coordinatingAccessAt: cloudFileUrl)
                    if exists && !isDir {
                        if let newUrl = await fileBookmarkController.loadBookmark(fileId: unconvertedFileUrl.fileId) {
                            location = locationFileManager.fileLocation(for: newUrl) ?? unconvertedFileUrl.location
                            fullURL = newUrl
                        } else {
                            fullURL = cloudFileUrl
                        }
                    } else {
                        do {
                            fullURL = try await locationFileManager.create(id: fileId, location: location, pathExtension: pathExtension, data: oldData, cloudUrl: cloudFileUrl)
                        } catch {
                            location = .appCloud
                            Logger.fileStore.error("Cannot create file in iCloud \(error.localizedDescription, privacy: .public)")
                        }
                    }
                } else {
                    location = .appCloud
                }
            }
            if fullURL == nil && location == .appCloud {
                do {
                    fullURL = try await locationFileManager.create(id: fileId, location: location, pathExtension: pathExtension, data: oldData)
                } catch {
                    Logger.fileStore.error("Cannot create file in appCloud \(error.localizedDescription, privacy: .public)")
                }
            }
            if fullURL == nil {
                location = .local
                do {
                    fullURL = try await locationFileManager.create(id: fileId, location: location, pathExtension: pathExtension, data: oldData)
                } catch {
                    Logger.fileStore.error("Cannot create file locally \(error.localizedDescription, privacy: .public)")
                    let fullUrl = try? await locationFileManager.createLocalUrl(id: fileId, pathExtension: pathExtension)
                    var fileUrl = FileUrl(fileId: fileId, url: fullUrl ?? URL(fileURLWithPath: ""), location: .local, module: unconvertedFileUrl.module, relativeUrl: locationFileManager.relativeUrl(for: fullURL))
                    fileUrl.resetData(oldData) // added if any platform has issue to save data.
                    return fileUrl
                }
            }
        }
        if let fullURL {
            let _ = fullURL.startAccessingSecurityScopedResource()
            defer { fullURL.stopAccessingSecurityScopedResource() }
            do {
                try await fileBookmarkController.saveBookmark(fileId: fileId, fileUrl: fullURL)
            } catch {
                Logger.fileStore.error("Cannot create file locally \(error.localizedDescription, privacy: .public)")
            }
            var fileUrl = FileUrl(fileId: fileId, url: fullURL, location: locationFileManager.fileLocation(for: fullURL), module: unconvertedFileUrl.module, relativeUrl: locationFileManager.relativeUrl(for: fullURL))
            fileUrl.resetData(oldData) // added if any platform has issue to save data.
            return fileUrl
        } else {
            return nil
        }
    }

}

// MARK: - Validate

extension FileUrlDataController: FileAccessible {
    private func filterUrls(callBlock: (FileUrl) async -> Bool) async -> [FileUrl] {
        await someFileUrls(from: await fileUrlAccess.fetchFileUrl(), callBlock: callBlock)
    }

    private func someFileUrls(from allFileUrls: [FileUrl], callBlock: (FileUrl) async -> Bool) async -> [FileUrl] {
        var invalidUrls: [FileUrl] = []
        for fileUrl in allFileUrls {
            let readable = await callBlock(fileUrl)
            if readable {
                invalidUrls.append(fileUrl)
            }
        }
        return invalidUrls
    }

    public func validateFiles() async -> Bool {
        let fileUrls = await filterUrls { fileUrl in
            await !canRead(for: fileUrl)
        }
        var result: Bool = true
        for fileUrl in fileUrls {
            let newResult = await validateFiles(fileUrls: [fileUrl])
            result = newResult && result
        }
        return result
    }

    public func validateFiles(root: URL) async -> Int {
        let fileUrls = await filterUrls { fileUrl in
            await !hasAccess(for: fileUrl)
        }
        guard !fileUrls.isEmpty else { return 0 }
        await self.validateFiles(fileUrls: fileUrls, withRoot: root)

        let fileUrlsAfterValidations = await filterUrls { fileUrl in
            await !hasAccess(for: fileUrl)
        }
        return fileUrlsAfterValidations.count
    }

    private func validateFiles(fileUrls: [FileUrl]) async -> Bool {
        guard !fileUrls.isEmpty else { return true }
        let folderKeys = await fileBookmarkController.folders()
        for folderId in folderKeys {
            if let folderUrl = await self.fileBookmarkController.loadBookmark(fileId: folderId, folder: true) {
                let files = await someFileUrls(from: fileUrls) { fileUrl in
                    await !hasAccess(for: fileUrl)
                }
                await self.validateFiles(fileUrls: files, withRoot: folderUrl)
            }
        }
        let filesAfterValidation = await someFileUrls(from: fileUrls) { fileUrl in
            await !canRead(for: fileUrl)
        }
        return filesAfterValidation.isEmpty
    }

    private func validateFiles(fileUrls: [FileUrl], withRoot url: URL) async {
        guard !fileUrls.isEmpty else { return }
        do {
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }

            if url.scheme == nil {
                Logger.fileStore.error("scheme is nil")
            }
            var error: NSError? = nil
            NSFileCoordinator().coordinate(readingItemAt: url, error: &error) { (url) in
                let keys : [URLResourceKey] = [.nameKey, .isDirectoryKey, .ubiquitousItemDownloadingStatusKey]
                guard let fileList =
                        FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys) else {
                    Logger.fileStore.error("*** Unable to access the contents of \(url.path, privacy: .public) ***\n")
                    return
                }

                for case let file as URL in fileList {
                    guard url.startAccessingSecurityScopedResource() else { continue }
                    defer { url.stopAccessingSecurityScopedResource() }

                    let fileName = file.lastPathComponent
                    let isNotDownloaded = fileName.starts(with: ".") && fileName.hasSuffix(".icloud")
                    let compName = isNotDownloaded ? String(String(fileName.dropFirst()).dropLast(".icloud".count)) : fileName
                    let checkFiles = fileUrls.filter { $0.rawUrl.lastPathComponent == compName }

                    let values = try? file.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])

                    let path = file.deletingLastPathComponent()
                    for fileUrl in checkFiles {
                        guard absoluteFileName(for: fileUrl).starts(with: path.absoluteString) else { continue }
                        // found one
                        if isNotDownloaded || (values?.ubiquitousItemDownloadingStatus ?? .notDownloaded) == .notDownloaded {
                            do {
                                try FileManager.default.startDownloadingUbiquitousItem(at: file)
                            } catch {
                                print(error.localizedDescription)
                            }
                        }
                        //Task.detached(priority: .userInitiated) {
                            do {
                                try fileBookmarkController.saveBookmarkSync(fileId: fileUrl.fileId, fileUrl: file)
                            } catch {
                                print(error.localizedDescription)
                            }
                        //}
                    }

                }
            }
        }
    }
}

// MARK: - Manage files
extension FileUrlDataController {
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

    public func move(fileUrl: FileUrl?, from source: String, to destination: String) async -> FileUrl? {
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

struct FakeFileFileAccessible: FileUrlAccessible {
    func fileUrl(item: any Observable) async -> FileUrl? { nil }    
    func setFileUrl(_ fileUrl: FileUrl?, item: any Observable) async {}
    func fetchFileUrl() async -> [FileUrl] { [] }
    func saveFileUrl(fileUrl: FileUrl) async {}
    func moveFiles() async throws {}
}
