// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import DiceRPG
import Foundation
import AudioRPG
import PdfRPG
import PhotoRPG
import TableRPG
import CharacterRPG
import Testing

@testable import MapRPG

struct ExportControllerTests {
    @Test func exportingAll() async throws {
        let root = try await MockRoot.importTestData()
        await root.itemController.resetData()

        let sut = root.exportController

        var ids = await sut.exportingAll()
        try #require(ids.ids[.map] != nil)
        #expect(ids.ids[.map]!.isEmpty)

        let itemId = await root.itemController.addNew(type: nil).itemId
        ids = await sut.exportingAll()
        try #require(ids.ids[.map] != nil)
        #expect(ids.ids[.map]! == [itemId])

        let newId = await root.itemController.addNew(type: nil).itemId
        let entry = await MapEntryModel(id: UUID(), name: "Nothing", content: root.linkController.generateLink(itemId: newId), coordinates: [])
        await root.itemController.itemOrEmpty(for: itemId).entries.append(entry)

        ids = await sut.exportingAll()
        try #require(ids.ids[.map] != nil)
        #expect(ids.ids[.map]!.count == 2)
    }

    @Test func exporting() async throws {
        let root = try await MockRoot.importTestData()
        await root.itemController.resetData()

        let sut = root.exportController

        let itemId = await root.itemController.addNew(type: nil).itemId

        let newId = await root.itemController.addNew(type: nil).itemId
        let url = await root.itemController.itemOrEmpty(for: newId).url(linkNumber: 0)
        let entry = MapEntryModel(id: UUID(), name: "Nothing", content: "\(url)", coordinates: [])
        await root.itemController.itemOrEmpty(for: itemId).entries.append(entry)

        var ids = await sut.exporting(itemIds: ItemModuleIds(ids: Set(arrayLiteral: itemId), module: .map))
        var mapIds = ids.ids[.map]
        try #require(mapIds != nil)
        #expect(mapIds!.count == 2)
        #expect(mapIds!.contains(itemId))
        #expect(mapIds!.contains(newId))

        let notConnected = await root.itemController.addNew(type: nil).itemId
        ids = await sut.exporting(itemIds: ItemModuleIds(ids: Set([itemId]), module: .map))
        mapIds = ids.ids[.map]
        try #require(mapIds != nil)
        #expect(mapIds!.count == 2)
        #expect(mapIds!.contains(itemId))
        #expect(mapIds!.contains(newId))
        #expect(!mapIds!.contains(notConnected))
    }
}
#endif
