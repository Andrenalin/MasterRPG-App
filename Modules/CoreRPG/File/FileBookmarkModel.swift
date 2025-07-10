// @copyright André Trettin

import Foundation
import os.log

actor FileBookmarkModel {
    init(name: String, priority: TaskPriority) {
        itemController = FileDataController(name: name, priority: priority)
        Task {
            await fetch()
        }
    }

    private static let deviceId = UUID(uuidString: "F4AC90DF-36F2-4151-B283-F0CF9D0BAC33")!
    private static let folderId = UUID(uuidString: "8393e8f6-f6d2-11ed-b67e-0242ac120002")!

    private var fileBookmarks: [UUID: Data] = [:]
    private var folderBookmarks: [UUID: Data] = [:]

    private struct Bookmarks: Codable, Storeable, Sendable {
        let id: UUID
        let bookmarks: [UUID: Data]
    }
    private let itemController: FileDataController<Bookmarks>

    func bookmarkData(for fileId: UUID, folder: Bool) -> Data? {
        folder ? folderBookmarks[fileId] : fileBookmarks[fileId]
    }

    func changeBookmarks(fileId: UUID, data: Data, folder: Bool) async {
        if folder {
            folderBookmarks[fileId] = data
        } else {
            fileBookmarks[fileId] = data
        }
        await save()
    }

    func folders() -> [UUID] {
        Array(folderBookmarks.keys)
    }

    func removeBookmark(fileId: UUID) async {
        fileBookmarks.removeValue(forKey: fileId)
        folderBookmarks.removeValue(forKey: fileId)
        await save()
    }

    private func fetch() async {
        await itemController.fetch()
        let fileData = await itemController.read(id: Self.deviceId)?.bookmarks ?? [:]
        let folderData = await itemController.read(id: Self.folderId)?.bookmarks ?? [:]

        fileBookmarks = fileData
        folderBookmarks = folderData
    }

    private func save() async {
        let file = fileBookmarks
        let folder = folderBookmarks
        await itemController.replace(data: Bookmarks(id: Self.deviceId, bookmarks: file))
        await itemController.replace(data: Bookmarks(id: Self.folderId, bookmarks: folder))
        await itemController.save()
    }
}

public struct FileBookmarkController: Sendable {
    public init(module: String, priority: TaskPriority = .utility) {
        self.priority = priority
        fileBookmarkModel = FileBookmarkModel(name: FileBookmarkController.name(from: module), priority: priority)
    }

    public init(name: String, priority: TaskPriority = .utility) {
        self.priority = priority
        fileBookmarkModel = FileBookmarkModel(name: name, priority: priority)
    }

    let fileBookmarkModel: FileBookmarkModel
    let priority: TaskPriority
    
    static func name(from module: String) -> String {
        module[module.startIndex..<module.index(before: module.endIndex)].lowercased() + "Bookmarks"
    }
}

extension FileBookmarkController {
    func folders() async -> [UUID] {
        await fileBookmarkModel.folders()
    }

    func loadBookmark(fileId: UUID, folder: Bool = false) async -> URL? {
        guard let data = await fileBookmarkModel.bookmarkData(for: fileId, folder: folder) else { return nil }
        return await loadBookmark(fileId: fileId, data: data, folder: folder)
    }
    
    private func loadBookmark(fileId: UUID, data: Data, folder: Bool = false) async -> URL? {
        do {
#if os(macOS)
            let options = URL.BookmarkResolutionOptions.withSecurityScope
#else
            let options: URL.BookmarkResolutionOptions = []
#endif
            var isStale = false
            let url = try URL(resolvingBookmarkData: data, options: options, relativeTo: nil, bookmarkDataIsStale: &isStale)
            if isStale {
                Logger.bookmarkStore.info("Stale Bookmark: \(url.absoluteString, privacy: .public)")
                let _ = url.startAccessingSecurityScopedResource()
                defer { url.stopAccessingSecurityScopedResource() }
                try await saveBookmark(fileId: fileId, fileUrl: url, folder: folder)
            }
            return url
        } catch {
            Logger.bookmarkStore.error("Resolving Bookmark: \(fileId, privacy: .public) with error: \(error.localizedDescription, privacy: .public)")
        }
        return nil
    }
    
    func saveBookmark(fileId: UUID, fileUrl: URL, folder: Bool = false) async throws {
#if os(macOS)
        let options = URL.BookmarkCreationOptions.withSecurityScope
#else
        let options = URL.BookmarkCreationOptions.suitableForBookmarkFile
#endif
        let data = try fileUrl.bookmarkData(
            options: options,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        await changeBookmark(fileId: fileId, data: data, folder: folder)
    }

    func saveBookmarkSync(fileId: UUID, fileUrl: URL, folder: Bool = false) throws {
#if os(macOS)
        let options = URL.BookmarkCreationOptions.withSecurityScope
#else
        let options = URL.BookmarkCreationOptions.suitableForBookmarkFile
#endif
        let data = try fileUrl.bookmarkData(
            options: options,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        Task {
            await changeBookmark(fileId: fileId, data: data, folder: folder)
        }
    }

    func removeBookmark(fileId: UUID) {
        let model = fileBookmarkModel
        Task.detached(priority: priority) {
            await model.removeBookmark(fileId: fileId)
        }
    }
}

private extension FileBookmarkController {
    func changeBookmark(fileId: UUID, data: Data, folder: Bool) async {
        let model = fileBookmarkModel
        await model.changeBookmarks(fileId: fileId, data: data, folder: folder)
    }
}
