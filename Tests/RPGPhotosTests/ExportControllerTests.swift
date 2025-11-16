// @copyright André Trettin

#if canImport(Testing)
import AndrenalinKit
import Foundation
import RPGResourcesDebug
import Testing

@testable import RPGPhotos

struct ExportControllerTests {
    @Test func exportingAll() async throws {
        let root = await PhotoRootModel.testRoot()
        await root.itemController.resetData()

        let sut = root.exportController

        var ids = await sut.exportingAll()
        try #require(ids.ids[.photo] != nil)
        #expect(ids.ids[.photo]!.isEmpty)

        let itemId = await root.itemController.addNew(type: nil).itemId
        ids = await sut.exportingAll()
        try #require(ids.ids[.photo] != nil)
        #expect(ids.ids[.photo]! == [itemId])

        let newId = await root.itemController.addNew(type: nil).itemId
        let entry = PhotoEntryModel(id: UUID(), photoId: newId)
        await root.itemController.itemOrEmpty(for: itemId).entries.append(entry)

        ids = await sut.exportingAll()
        try #require(ids.ids[.photo] != nil)
        #expect(ids.ids[.photo]!.count == 2)
    }

    @Test func exporting() async throws {
        let root = await PhotoRootModel.testRoot()
        await root.itemController.resetData()

        let sut = root.exportController

        let itemId = await root.itemController.addNew(type: nil).itemId

        let newId = await root.itemController.addNew(type: nil).itemId
        let entry = PhotoEntryModel(id: UUID(), photoId: newId)
        await root.itemController.itemOrEmpty(for: itemId).entries.append(entry)

        var ids = await sut.exporting(itemIds: ItemModuleIds(ids: Set(arrayLiteral: itemId), module: .photo))
        var photoIds = ids.ids[.photo]
        try #require(photoIds != nil)
        #expect(photoIds!.count == 2)
        #expect(photoIds!.contains(itemId))
        #expect(photoIds!.contains(newId))

        let notConnected = await root.itemController.addNew(type: nil).itemId
        ids = await sut.exporting(itemIds: ItemModuleIds(ids: Set([itemId]), module: .photo))
        photoIds = ids.ids[.photo]
        try #require(photoIds != nil)
        #expect(photoIds!.count == 2)
        #expect(photoIds!.contains(itemId))
        #expect(photoIds!.contains(newId))
        #expect(!photoIds!.contains(notConnected))
    }
}
#endif
