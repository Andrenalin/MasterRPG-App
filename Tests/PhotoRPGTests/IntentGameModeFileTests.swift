// @copyright André Trettin

import CoreRPG
import Foundation
import Testing

@testable import PhotoRPG

/// CODE_AUDIT_Since_3.0.1 §5.2: the file a Create intent attaches during a game reached only a
/// game copy of the new item. With `forceSave` it is stored on the library item.
@Suite("Intent file writes during a game")
@MainActor
struct IntentGameModeFileTests {
    private func fileUrl(for itemId: UUID) -> FileUrl {
        FileUrl(fileId: itemId, url: URL(filePath: "/Photo/Map Scroll.jpg"), location: .newCloud, module: "photo", relativeUrl: nil)
    }

    @Test("A file attached to a created photo is stored on the library item")
    func fileOfCreatedItemIsStoredInLibrary() {
        let root = PhotoRootModel.testRoot()
        let data = root.itemController.itemDataModel
        data.isGameMode = true
        let created = PhotoModel(id: UUID(), name: "Map Scroll")
        root.itemController.replace(model: created, isInsert: true, forceSave: true)

        root.editController.reset(fileUrl: fileUrl(for: created.id), itemId: created.id, forceSave: true)

        #expect(root.itemController.itemSync(for: created.id, noGame: true)?.fileUrl == fileUrl(for: created.id))
        #expect(data.gameItemData[created.id] == nil)
    }

    @Test("Without forceSave the file still only reaches game memory, as for the editor in a game")
    func defaultStaysInGameMemory() {
        let root = PhotoRootModel.testRoot()
        let data = root.itemController.itemDataModel
        data.isGameMode = true
        let created = PhotoModel(id: UUID(), name: "Map Scroll")
        root.itemController.replace(model: created, isInsert: true, forceSave: true)

        root.editController.reset(fileUrl: fileUrl(for: created.id), itemId: created.id)

        #expect(root.itemController.itemSync(for: created.id, noGame: true)?.fileUrl == nil)
        #expect((data.gameItemData[created.id] as? PhotoModel)?.fileUrl == fileUrl(for: created.id))
    }
}
