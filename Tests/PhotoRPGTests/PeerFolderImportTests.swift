// @copyright André Trettin

#if canImport(Testing)
import Foundation
import Testing

@testable import CoreRPG
@testable import PhotoRPG

/// CODE_AUDIT_24 §6.5: a folder in a peer's package is sanitised like every other item.
@Suite(.serialized)
@MainActor
struct PeerFolderImportTests {
    @Test("A peer's folder cannot bring a traversal file url into the library")
    func peerFolderFileUrlIsSanitized() async throws {
        let source = PhotoRootModel.testRoot()
        let folderId = await source.itemController.addNew(type: .folder)
        let childId = await source.itemController.addNew(type: .item)
        source.editController.reset(name: "Folder", itemId: folderId)
        source.editController.reset(name: "Child", itemId: childId)
        source.editController.addItem(itemId: childId, parentId: folderId)
        let hostile = FileUrl(
            fileId: UUID(),
            url: try #require(URL(string: "../../Stores/Private/private.sqlite")),
            location: .newCloud,
            module: "Photos",
            relativeUrl: nil
        )
        try #require(source.itemController.itemSync(for: folderId, noGame: true)).fileUrl = hostile

        let exportIds = source.exportController.exporting(itemIds: ItemModuleIds(ids: [folderId, childId], module: .photo))
        let output = OutputStream.toMemory()
        output.open()
        _ = try await source.exportController.export(itemIds: exportIds, into: output)
        output.close()
        let data = try #require(output.property(forKey: Stream.PropertyKey.dataWrittenToMemoryStreamKey) as? Data)

        let destination = PhotoRootModel.testRoot()
        let input = InputStream(data: data)
        input.open()
        defer { input.close() }
        let model = ItemDataImportModel(importMode: .overwrite, peerPolicy: PeerImportPolicy(primaryItemId: UUID()))
        try await destination.importController.importStream(from: input, forceSave: true, importModel: model)

        let imported = try #require(destination.itemController.itemSync(for: folderId, noGame: true), "the folder arrived")
        #expect(imported.isFolder)
        if let fileUrl = imported.fileUrl {
            #expect(!fileUrl.rawUrl.pathComponents.contains(".."))
        }
    }
}
#endif
