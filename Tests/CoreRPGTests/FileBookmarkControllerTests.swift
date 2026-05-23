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
}
