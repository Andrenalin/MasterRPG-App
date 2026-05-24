// @copyright André Trettin

import CoreRPG
import Foundation
import DiceRPG
import PdfRPG
import PhotoRPG
import TableRPG
import RPGResourcesDebug
import Testing

@testable import CharacterRPG

struct ImportControllerTests {
    @Test func importing() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        
        let sut = await root.importController

        let bundle = ResourcesDebug.bundle
        let url = bundle.url(forResource: ResourcesDebug.valueTestData, withExtension: "gmz").unsafelyUnwrapped

        let task = sut.importUrl(from: url)
        let _ = try await task.value
        #expect(await root.itemController.itemDataModel.items.count == 15)
    }
    
    @Test func importingItemInFolderWithExcludesSiblings() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)

        let sut = await root.importController

        let exportController = await root.exportController
        let edit = await root.editController

        let folder = await edit.addNew(type: .folder)
        try #require(folder != nil)
        let folderId = folder!.id

        let itemId = await root.itemController.addNew(type: .item)
        let siblingId = await root.itemController.addNew(type: .item)
        await edit.addItem(itemId: itemId, parentId: folderId)
        await edit.addItem(itemId: siblingId, parentId: folderId)

        let ids = await exportController.exporting(itemIds: ItemModuleIds(ids: Set([itemId]), module: .value))
        let stream = OutputStream.toMemory()
        stream.open()
        defer { stream.close() }

        _ = try await exportController.export(itemIds: ids, into: stream) { _, _ in }

        let data = stream.property(forKey: Stream.PropertyKey.dataWrittenToMemoryStreamKey) as? Data
        try #require(data != nil)

        await edit.delete(itemId: folderId)
        await root.itemController.delete(itemId: folderId)
        await edit.delete(itemId: itemId)
        await root.itemController.delete(itemId: itemId)
        await edit.delete(itemId: siblingId)
        await root.itemController.delete(itemId: siblingId)

        #expect(await root.itemController.itemDataModel.items.contains(itemId) == false)
        #expect(await root.itemController.itemDataModel.items.contains(folderId) == false)
        #expect(await root.itemController.itemDataModel.items.contains(siblingId) == false)

        let importStream = InputStream(data: data!)
        importStream.open()
        defer { importStream.close() }

        try await sut.importStream(from: importStream, forceSave: false, counterUpdater: {})

        #expect(await root.itemController.itemDataModel.items.contains(itemId))
        #expect(await root.itemController.itemDataModel.items.contains(folderId))
        #expect(await root.itemController.itemDataModel.items.contains(siblingId) == false)
    }

}
