// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import Foundation
import PhotoRPG
import RPGResourcesDebug
import Testing

@testable import WeatherRPG

@MainActor
struct ExportControllerTests {
    @Test func exportingAll() async throws {
        let root = WeatherRootModel.testRoot(photoRoot: PhotoRootModel.testRoot())
        await root.itemController.resetData()

        let sut = root.exportController

        var ids = sut.exportingAll()
        try #require(ids.ids[.weather] != nil)
        #expect(ids.ids[.weather]!.isEmpty)

        let itemId = await root.itemController.addNew(type: .item)
        ids = sut.exportingAll()
        try #require(ids.ids[.weather] != nil)
        #expect(ids.ids[.weather]! == [itemId])

        let _ = await root.itemController.addNew(type: .item)
        ids = sut.exportingAll()
        try #require(ids.ids[.weather] != nil)
        #expect(ids.ids[.weather]!.count == 2)
    }

    @Test func exportingAllAfterDeletion() async throws {
        let root = WeatherRootModel.testRoot(photoRoot: PhotoRootModel.testRoot())
        await root.itemController.resetData()

        let sut = root.exportController
        let edit = root.editController

        let item = await edit.addNew(type: .item)
        let deleted = await edit.addNew(type: .item)
        try #require(item != nil)
        try #require(deleted != nil)
        edit.reset(name: "keep", itemId: item!.id)
        edit.reset(name: "delete", itemId: deleted!.id)

        await edit.delete(itemId: deleted!.id)

        let ids = sut.exportingAll()
        try #require(ids.ids[.weather] != nil)
        #expect(ids.ids[.weather]!.contains(item!.id))
        #expect(!ids.ids[.weather]!.contains(deleted!.id))
        #expect(ids.ids[.weather]!.count == 1)
    }

    @Test func exporting() async throws {
        let root = WeatherRootModel.testRoot(photoRoot: PhotoRootModel.testRoot())
        await root.itemController.resetData()

        let sut = root.exportController

        let itemId = await root.itemController.addNew(type: .item)

        let newId = await root.itemController.addNew(type: .item)

        var ids = sut.exporting(itemIds: ItemModuleIds(ids: Set(arrayLiteral: itemId), module: .weather))
        var weatherIds = ids.ids[.weather]
        try #require(weatherIds != nil)
        #expect(weatherIds!.count == 1)
        #expect(weatherIds!.contains(itemId))
        #expect(!weatherIds!.contains(newId))

        let notConnected = await root.itemController.addNew(type: .item)
        ids = sut.exporting(itemIds: ItemModuleIds(ids: Set([itemId, notConnected]), module: .weather))
        weatherIds = ids.ids[.weather]
        try #require(weatherIds != nil)
        #expect(weatherIds!.count == 2)
        #expect(weatherIds!.contains(itemId))
        #expect(!weatherIds!.contains(newId))
        #expect(weatherIds!.contains(notConnected))
    }
}
#endif
