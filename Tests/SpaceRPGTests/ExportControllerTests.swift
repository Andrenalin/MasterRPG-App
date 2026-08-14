// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import Foundation
import RPGResourcesDebug
import Testing

@testable import SpaceRPG

@MainActor
struct ExportControllerTests {
    @Test func exportingAll() async throws {
        let root = SpaceRootModel.testRoot()
        await root.itemController.resetData()

        let sut = root.exportController

        var ids = sut.exportingAll()
        try #require(ids.ids[.space] != nil)
        #expect(ids.ids[.space]!.isEmpty)

        let itemId = await root.itemController.addNew(type: .item)
        ids = sut.exportingAll()
        try #require(ids.ids[.space] != nil)
        #expect(ids.ids[.space]! == [itemId])

        let newId = await root.itemController.addNew(type: .item)
        let entry = SpaceEntryModel(id: UUID(), spaceId: newId)
        root.itemController.itemOrEmpty(for: itemId).entries.append(entry)

        ids = sut.exportingAll()
        try #require(ids.ids[.space] != nil)
        #expect(ids.ids[.space]!.count == 2)
    }

    @Test func exporting() async throws {
        let root = SpaceRootModel.testRoot()
        await root.itemController.resetData()

        let sut = root.exportController

        let itemId = await root.itemController.addNew(type: .item)

        let newId = await root.itemController.addNew(type: .item)
        let entry = SpaceEntryModel(id: UUID(), spaceId: newId)
        root.itemController.itemOrEmpty(for: itemId).entries.append(entry)

        var ids = sut.exporting(itemIds: ItemModuleIds(ids: Set(arrayLiteral: itemId), module: .space))
        var spaceIds = ids.ids[.space]
        try #require(spaceIds != nil)
        #expect(spaceIds!.count == 2)
        #expect(spaceIds!.contains(itemId))
        #expect(spaceIds!.contains(newId))

        let notConnected = await root.itemController.addNew(type: .item)
        ids = sut.exporting(itemIds: ItemModuleIds(ids: Set([itemId]), module: .space))
        spaceIds = ids.ids[.space]
        try #require(spaceIds != nil)
        #expect(spaceIds!.count == 2)
        #expect(spaceIds!.contains(itemId))
        #expect(spaceIds!.contains(newId))
        #expect(!spaceIds!.contains(notConnected))
    }
}
#endif
