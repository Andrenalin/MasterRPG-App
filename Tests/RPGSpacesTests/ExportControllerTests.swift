// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import Foundation
import RPGResourcesDebug
import Testing

@testable import SpaceRPG

struct ExportControllerTests {
    @Test func exportingAll() async throws {
        let root = await SpaceRootModel.testRoot()
        await root.itemController.resetData()

        let sut = await root.exportController

        var ids = await sut.exportingAll()
        try #require(ids.ids[.space] != nil)
        #expect(ids.ids[.space]!.isEmpty)

        let itemId = await root.itemController.addNew(type: .item)
        ids = await sut.exportingAll()
        try #require(ids.ids[.space] != nil)
        #expect(ids.ids[.space]! == [itemId])

        let newId = await root.itemController.addNew(type: .item)
        let entry = SpaceEntryModel(id: UUID(), spaceId: newId)
        await root.itemController.itemOrEmpty(for: itemId).entries.append(entry)

        ids = await sut.exportingAll()
        try #require(ids.ids[.space] != nil)
        #expect(ids.ids[.space]!.count == 2)
    }

    @Test func exporting() async throws {
        let root = await SpaceRootModel.testRoot()
        await root.itemController.resetData()

        let sut = await root.exportController

        let itemId = await root.itemController.addNew(type: .item)

        let newId = await root.itemController.addNew(type: .item)

        let _ = SpaceEntryModel(id: UUID(), spaceId: newId)
        var ids = await sut.exporting(itemIds: ItemModuleIds(ids: Set(arrayLiteral: itemId), module: .space))
        var spaceIds = ids.ids[.space]
        try #require(spaceIds != nil)
        #expect(spaceIds!.count == 1)
        #expect(spaceIds!.contains(itemId))
        #expect(!spaceIds!.contains(newId))

        let notConnected = await root.itemController.addNew(type: .item)
        ids = await sut.exporting(itemIds: ItemModuleIds(ids: Set([itemId, notConnected]), module: .space))
        spaceIds = ids.ids[.space]
        try #require(spaceIds != nil)
        #expect(spaceIds!.count == 2)
        #expect(spaceIds!.contains(itemId))
        #expect(!spaceIds!.contains(newId))
        #expect(spaceIds!.contains(notConnected))
    }
}
#endif
