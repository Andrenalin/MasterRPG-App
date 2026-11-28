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
        source.editController.reset(name: "Folder", itemId: folderId, forceSave: false)
        source.editController.reset(name: "Child", itemId: childId, forceSave: false)
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

    @Test("Many peer folders are each admitted with their own introduced children (§7.2)")
    func manyPeerFoldersKeepTheirOwnEntries() async throws {
        let source = PhotoRootModel.testRoot()
        var ids: Set<UUID> = []
        var childOfFolder: [UUID: UUID] = [:]
        for index in 0..<40 {
            let folderId = await source.itemController.addNew(type: .folder)
            let childId = await source.itemController.addNew(type: .item)
            source.editController.reset(name: "Folder \(index)", itemId: folderId, forceSave: false)
            source.editController.reset(name: "Child \(index)", itemId: childId, forceSave: false)
            source.editController.addItem(itemId: childId, parentId: folderId)
            ids.formUnion([folderId, childId])
            childOfFolder[folderId] = childId
        }
        let exportIds = source.exportController.exporting(itemIds: ItemModuleIds(ids: ids, module: .photo))
        let output = OutputStream.toMemory()
        output.open()
        _ = try await source.exportController.export(itemIds: exportIds, into: output)
        output.close()
        let data = try #require(output.property(forKey: Stream.PropertyKey.dataWrittenToMemoryStreamKey) as? Data)

        let destination = PhotoRootModel.testRoot()
        let input = InputStream(data: data)
        input.open()
        defer { input.close() }
        let model = ItemDataImportModel(importMode: .overwrite, peerPolicy: PeerImportPolicy(primaryItemId: UUID(), maximumItems: 200))
        try await destination.importController.importStream(from: input, forceSave: true, importModel: model)

        for (folderId, childId) in childOfFolder {
            let folder = try #require(destination.itemController.itemSync(for: folderId, noGame: true), "every folder arrived")
            #expect(folder.entries.map(\.childId) == [childId])
        }
    }
}
#endif
