// @copyright André Trettin

import Foundation
import os.log

actor FileBookmarkModel {
    init(name: String, priority: TaskPriority) {
        let itemController = FileDataController<Bookmarks>(name: name)
        self.itemController = itemController
        fetchTask = Task(priority: priority) {
            await itemController.fetch()
        }
    }

    private static let deviceId = UUID(uuidString: "F4AC90DF-36F2-4151-B283-F0CF9D0BAC33")!
    private static let folderId = UUID(uuidString: "8393e8f6-f6d2-11ed-b67e-0242ac120002")!

    private var fileBookmarks: [UUID: Data] = [:]
    private var folderBookmarks: [UUID: Data] = [:]
    private var didFetch = false

    private struct Bookmarks: Codable, Storable, Sendable {
        let id: UUID
        let bookmarks: [UUID: Data]
    }
    private let itemController: FileDataController<Bookmarks>
    private let fetchTask: Task<Void, Never>

    func bookmarkData(for fileId: UUID, folder: Bool) async -> Data? {
        await fetchIfNeeded()
        return folder ? folderBookmarks[fileId] : fileBookmarks[fileId]
    }

    func changeBookmarks(fileId: UUID, data: Data, folder: Bool) async {
        await fetchIfNeeded()
        if folder {
            folderBookmarks[fileId] = data
        } else {
            fileBookmarks[fileId] = data
        }
        await save()
    }

    func folders() async -> [UUID] {
        await fetchIfNeeded()
        return Array(folderBookmarks.keys)
    }

    func removeBookmark(fileId: UUID) async {
        await fetchIfNeeded()
        fileBookmarks.removeValue(forKey: fileId)
        folderBookmarks.removeValue(forKey: fileId)
        await save()
    }

    private func fetchIfNeeded() async {
        guard !didFetch else { return }
        await fetchTask.value
        let fileData = await itemController.read(id: Self.deviceId)?.bookmarks ?? [:]
        let folderData = await itemController.read(id: Self.folderId)?.bookmarks ?? [:]

        guard !didFetch else { return }
        fileBookmarks = fileData
        folderBookmarks = folderData
        didFetch = true
    }

    private var isSaving = false
    private var needsSave = false

    /// Rewrites the whole store, coalescing changes that arrive while a write is in flight into
    /// one follow-up write instead of one full rewrite per change. See CODE_AUDIT_15 §5.5.
    private func save() async {
        if isSaving {
            needsSave = true
            return
        }
        isSaving = true
        repeat {
            needsSave = false
            let file = fileBookmarks
            let folder = folderBookmarks
            await itemController.replace(data: Bookmarks(id: Self.deviceId, bookmarks: file))
            await itemController.replace(data: Bookmarks(id: Self.folderId, bookmarks: folder))
            await itemController.save()
        } while needsSave
        isSaving = false
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
    
    /// `@concurrent`, like `saveBookmark`: resolving and creating a security-scoped bookmark is
    /// IPC that ran on the caller's (often the main) actor. See CODE_AUDIT_21 §3.7.
    @concurrent
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
                Logger.bookmarkStore.info("Stale Bookmark: \(url.absoluteString, privacy: .private)")
                let securityScope = url.startSecurityScopedAccess()
                defer { securityScope.stop() }
                try await saveBookmark(fileId: fileId, fileUrl: url, folder: folder)
            }
            return url
        } catch {
            Logger.bookmarkStore.error("Resolving Bookmark: \(fileId, privacy: .public) with error: \(error.logIdentifier, privacy: .public) \(error.localizedDescription, privacy: .private)")
        }
        return nil
    }
    
    @concurrent
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

    func removeBookmark(fileId: UUID) {
        let model = fileBookmarkModel
        Task(priority: priority) {
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
