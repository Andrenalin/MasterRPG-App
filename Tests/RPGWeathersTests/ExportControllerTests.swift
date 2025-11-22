// @copyright André Trettin

#if canImport(Testing)
import AndrenalinKit
import Foundation
import PhotoRPG
import RPGResourcesDebug
import Testing

@testable import WeatherRPG

struct ExportControllerTests {
    @Test func exportingAll() async throws {
        let root = await WeatherRootModel.testRoot(photoRoot: PhotoRootModel.testRoot())
        await root.itemController.resetData()

        let sut = root.exportController

        var ids = await sut.exportingAll()
        try #require(ids.ids[.weather] != nil)
        #expect(ids.ids[.weather]!.isEmpty)

        let itemId = await root.itemController.addNew(type: nil).itemId
        ids = await sut.exportingAll()
        try #require(ids.ids[.weather] != nil)
        #expect(ids.ids[.weather]! == [itemId])

        let _ = await root.itemController.addNew(type: nil).itemId
        ids = await sut.exportingAll()
        try #require(ids.ids[.weather] != nil)
        #expect(ids.ids[.weather]!.count == 2)
    }

    @Test func exporting() async throws {
        let root = await WeatherRootModel.testRoot(photoRoot: PhotoRootModel.testRoot())
        await root.itemController.resetData()

        let sut = root.exportController

        let itemId = await root.itemController.addNew(type: nil).itemId

        let newId = await root.itemController.addNew(type: nil).itemId

        var ids = await sut.exporting(itemIds: ItemModuleIds(ids: Set(arrayLiteral: itemId), module: .weather))
        var weatherIds = ids.ids[.weather]
        try #require(weatherIds != nil)
        #expect(weatherIds!.count == 1)
        #expect(weatherIds!.contains(itemId))
        #expect(!weatherIds!.contains(newId))

        let notConnected = await root.itemController.addNew(type: nil).itemId
        ids = await sut.exporting(itemIds: ItemModuleIds(ids: Set([itemId, notConnected]), module: .weather))
        weatherIds = ids.ids[.weather]
        try #require(weatherIds != nil)
        #expect(weatherIds!.count == 2)
        #expect(weatherIds!.contains(itemId))
        #expect(!weatherIds!.contains(newId))
        #expect(weatherIds!.contains(notConnected))
    }
}
#endif
