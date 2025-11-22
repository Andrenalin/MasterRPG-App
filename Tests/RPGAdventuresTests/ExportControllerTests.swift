// @copyright André Trettin

#if canImport(Testing)
import AndrenalinKit
import Foundation
import RPGDie
import AudioRPG
import RPGMaps
import PdfRPG
import PhotoRPG
import SpaceRPG
import RPGTables
import RPGValues
import Testing
import WeatherRPG

@testable import RPGAdventures

struct ExportControllerTests {
    @Test func exportingAll() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)

        let sut = root.exportController

        var ids = await sut.exportingAll()
        try #require(ids.ids[.adventure] != nil)
        #expect(ids.ids[.adventure]!.isEmpty)

        let itemId = await root.itemController.addNew(type: nil).itemId
        ids = await sut.exportingAll()
        try #require(ids.ids[.adventure] != nil)
        #expect(ids.ids[.adventure]! == [itemId])

        let newId = await root.itemController.addNew(type: nil).itemId
        let entry = await AdventureEntryModel(id: UUID(), name: "Nothing", content: root.linkController.generateLink(itemId: newId))
        await root.itemController.itemOrEmpty(for: itemId).entries.append(entry)

        ids = await sut.exportingAll()
        try #require(ids.ids[.adventure] != nil)
        #expect(ids.ids[.adventure]!.count == 2)
    }

    @Test func exporting() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)

        let sut = root.exportController

        let itemId = await root.itemController.addNew(type: nil).itemId

        let newId = await root.itemController.addNew(type: nil).itemId
        let url = await root.itemController.itemOrEmpty(for: newId).url(linkNumber: 0)
        let entry = AdventureEntryModel(id: UUID(), name: "Nothing", content: "\(url)")
        await root.itemController.itemOrEmpty(for: itemId).entries.append(entry)

        var ids = await sut.exporting(itemIds: ItemModuleIds(ids: Set(arrayLiteral: itemId), module: .adventure))
        var adventureIds = ids.ids[.adventure]
        try #require(adventureIds != nil)
        #expect(adventureIds!.count == 2)
        #expect(adventureIds!.contains(itemId))
        #expect(adventureIds!.contains(newId))

        let notConnected = await root.itemController.addNew(type: nil).itemId
        ids = await sut.exporting(itemIds: ItemModuleIds(ids: Set([itemId]), module: .adventure))
        adventureIds = ids.ids[.adventure]
        try #require(adventureIds != nil)
        #expect(adventureIds!.count == 2)
        #expect(adventureIds!.contains(itemId))
        #expect(adventureIds!.contains(newId))
        #expect(!adventureIds!.contains(notConnected))
    }
}
#endif
