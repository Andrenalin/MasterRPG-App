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

    static let deviceId = UUID(uuidString: "F4AC90DF-36F2-4151-B283-F0CF9D0BAC33")!
    static let folderId = UUID(uuidString: "8393e8f6-f6d2-11ed-b67e-0242ac120002")!

    private var fileBookmarks: [UUID: Data] = [:]
    private var folderBookmarks: [UUID: Data] = [:]
    private var didFetch = false

    private struct Bookmarks: Codable, Storable, Sendable {
        let id: UUID
        let bookmarks: [UUID: Data]
    }
    private let itemController: FileDataController<Bookmarks>
    private let fetchTask: Task<Bool, Never>
    /// Changes made while the stored file could not be read. They are merged into the stored
    /// bookmarks once a read succeeds and are never written over the unread file.
    private var pendingRemovals: Set<UUID> = []
    private var hasPendingChanges = false

    func bookmarkData(for fileId: UUID, folder: Bool) async -> Data? {
        _ = await fetchIfNeeded()
        return folder ? folderBookmarks[fileId] : fileBookmarks[fileId]
    }

    func changeBookmarks(fileId: UUID, data: Data, folder: Bool) async {
        let isFetched = await fetchIfNeeded()
        pendingRemovals.remove(fileId)
        if folder {
            folderBookmarks[fileId] = data
        } else {
            fileBookmarks[fileId] = data
        }
        guard isFetched else {
            hasPendingChanges = true
            return
        }
        await save()
    }

    func folders() async -> [UUID] {
        _ = await fetchIfNeeded()
        return Array(folderBookmarks.keys)
    }

    func removeBookmark(fileId: UUID) async {
        let isFetched = await fetchIfNeeded()
        fileBookmarks.removeValue(forKey: fileId)
        folderBookmarks.removeValue(forKey: fileId)
        guard isFetched else {
            pendingRemovals.insert(fileId)
            hasPendingChanges = true
            return
        }
        await save()
    }

    /// - Returns: `false` while the stored bookmarks cannot be read. The read is retried on the
    ///   next call; a failed read is never taken as "no bookmarks". See CODE_AUDIT_23 §5.5.
    private func fetchIfNeeded() async -> Bool {
        guard !didFetch else { return true }
        var isFetched = await fetchTask.value
        if !isFetched, !didFetch {
            isFetched = await itemController.fetch()
        }
        guard !didFetch else { return true }
        guard isFetched else { return false }
        // An entry that is stored but cannot be decoded (a changed `Bookmarks` shape) reads as
        // "no bookmarks"; the next save would write a fresh row over it. It counts as a failed
        // read instead: nothing is marked fetched or saved, and the changes stay in memory.
        // See CODE_AUDIT_24 §5.12.
        guard await !itemController.isUndecodable(id: Self.deviceId),
              await !itemController.isUndecodable(id: Self.folderId) else {
            Logger.bookmarkStore.error("The stored bookmarks cannot be decoded and are left untouched")
            return false
        }
        let fileData = await itemController.read(id: Self.deviceId)?.bookmarks ?? [:]
        let folderData = await itemController.read(id: Self.folderId)?.bookmarks ?? [:]

        guard !didFetch else { return true }
        fileBookmarks = fileData.merging(fileBookmarks) { _, new in new }
        folderBookmarks = folderData.merging(folderBookmarks) { _, new in new }
        for fileId in pendingRemovals {
            fileBookmarks.removeValue(forKey: fileId)
            folderBookmarks.removeValue(forKey: fileId)
        }
        didFetch = true
        if hasPendingChanges {
            hasPendingChanges = false
            pendingRemovals = []
            await save()
        }
        return true
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
                // The resolved URL is usable even when the refresh cannot be saved.
                // See CODE_AUDIT_23 §5.25.
                do {
                    try await saveBookmark(fileId: fileId, fileUrl: url, folder: folder)
                } catch {
                    Logger.bookmarkStore.error("Refreshing stale Bookmark: \(fileId, privacy: .public) with error: \(error.logIdentifier, privacy: .public) \(error.localizedDescription, privacy: .private)")
                }
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
