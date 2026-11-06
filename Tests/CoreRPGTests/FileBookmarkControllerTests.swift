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
}
