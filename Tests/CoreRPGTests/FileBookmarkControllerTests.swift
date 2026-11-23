// @copyright André Trettin

import Foundation
import Testing

@testable import CoreRPG

struct FileBookmarkControllerTests {

    @Test func createFileBookmark() async throws {
        let sut = FileBookmarkModel(name: "MegaTest", priority: .userInitiated)
        #expect(await sut.folders().isEmpty)
    }

    @Test func foldersEmpty() async throws {
        let sut = FileBookmarkController(name: "MegaTest", priority: .userInitiated)
        #expect(await sut.folders().isEmpty)
    }

    @Test func saveAndLoad() async throws {
        let sut = FileBookmarkController(name: "MegaTest", priority: .userInitiated)
        let id = UUID()
        let url = URL.cachesDirectory
        try await sut.saveBookmark(fileId: id, fileUrl: url)

        let loadedURL = await sut.loadBookmark(fileId: id)
        #expect(loadedURL == url)
    }
    
    @Test func moduleName() async throws {
        let name = FileBookmarkController.name(from: NetworkModules.photo.token)
        #expect(name == "photoBookmarks")
    }

    @Test("An undecodable bookmark row is never written over (§5.12)")
    func undecodableBookmarkRowIsKept() async throws {
        let name = "BookmarkAudit\(UUID().uuidString)"
        let storeUrl = (FileManager.groupURL ?? URL.documentsDirectory).appending(path: "\(name).json")
        defer { try? FileManager.default.removeItem(at: storeUrl) }
        struct Row: Codable { let id: UUID; let data: Data }
        let foreign = Data(#"{"shape":"from a newer build"}"#.utf8)
        let rows = [Row(id: FileBookmarkModel.deviceId, data: foreign)]
        try JSONEncoder().encode(rows).write(to: storeUrl)
        let before = try Data(contentsOf: storeUrl)

        let sut = FileBookmarkModel(name: name, priority: .userInitiated)
        let id = UUID()
        await sut.changeBookmarks(fileId: id, data: Data("new".utf8), folder: false)
        await sut.removeBookmark(fileId: UUID())

        #expect(try Data(contentsOf: storeUrl) == before, "the stored file is untouched")
        #expect(await sut.bookmarkData(for: id, folder: false) == Data("new".utf8), "the change still works in memory")
    }

    // CODE_AUDIT_28 §6.5: the app and the share extension each hold a copy of the store.
    @Test("A write keeps the bookmarks another process stored since this one read the file")
    func writeKeepsBookmarksOfAnotherProcess() async throws {
        let name = "BookmarkMerge\(UUID().uuidString)"
        let storeUrl = (FileManager.groupURL ?? URL.documentsDirectory).appending(path: "\(name).json")
        defer { try? FileManager.default.removeItem(at: storeUrl) }
        let app = FileBookmarkModel(name: name, priority: .userInitiated)
        let extensionProcess = FileBookmarkModel(name: name, priority: .userInitiated)
        // Both read the (still empty) store.
        _ = await app.bookmarkData(for: UUID(), folder: false)
        _ = await extensionProcess.bookmarkData(for: UUID(), folder: false)
        let fromApp = UUID()
        let fromExtension = UUID()

        await app.changeBookmarks(fileId: fromApp, data: Data("app".utf8), folder: false)
        await extensionProcess.changeBookmarks(fileId: fromExtension, data: Data("extension".utf8), folder: false)

        let reader = FileBookmarkModel(name: name, priority: .userInitiated)
        #expect(await reader.bookmarkData(for: fromApp, folder: false) == Data("app".utf8))
        #expect(await reader.bookmarkData(for: fromExtension, folder: false) == Data("extension".utf8))
    }

    @Test("A removal is written and does not bring back what another process removed")
    func removalIsMerged() async throws {
        let name = "BookmarkRemove\(UUID().uuidString)"
        let storeUrl = (FileManager.groupURL ?? URL.documentsDirectory).appending(path: "\(name).json")
        defer { try? FileManager.default.removeItem(at: storeUrl) }
        let first = FileBookmarkModel(name: name, priority: .userInitiated)
        let id = UUID()
        await first.changeBookmarks(fileId: id, data: Data("x".utf8), folder: false)

        await first.removeBookmark(fileId: id)

        let reader = FileBookmarkModel(name: name, priority: .userInitiated)
        #expect(await reader.bookmarkData(for: id, folder: false) == nil)
    }
}
