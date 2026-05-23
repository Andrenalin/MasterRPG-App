// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import Foundation
import DiceRPG
import AudioRPG
import MapRPG
import PdfRPG
import PhotoRPG
import SpaceRPG
import TableRPG
import CharacterRPG
import Testing
import WeatherRPG

@testable import AdventureRPG

struct ExportControllerTests {
    @Test func exportingAll() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)

        let sut = await root.exportController

        var ids = await sut.exportingAll()
        try #require(ids.ids[.adventure] != nil)
        #expect(ids.ids[.adventure]!.isEmpty)

        let itemId = await root.itemController.addNew(type: .item)
        ids = await sut.exportingAll()
        try #require(ids.ids[.adventure] != nil)
        #expect(ids.ids[.adventure]! == [itemId])

        let newId = await root.itemController.addNew(type: .item)
        let entry = await AdventureEntryModel(id: UUID(), name: "Nothing", content: root.linkController.generateLink(itemId: newId))
        await root.itemController.itemOrEmpty(for: itemId).entries.append(entry)

        ids = await sut.exportingAll()
        try #require(ids.ids[.adventure] != nil)
        #expect(ids.ids[.adventure]!.count == 2)
    }

    @Test func exportingAllAfterDeletion() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)

        let sut = await root.exportController
        let edit = await root.editController

        
        let item = await edit.addNew(type: .item)
        let deleted = await edit.addNew(type: .item)
        try #require(item != nil)
        try #require(deleted != nil)
        await edit.reset(name: "keep", itemId: item!.id)
        await edit.reset(name: "delete", itemId: deleted!.id)

        await edit.delete(itemId: deleted!.id)

        let ids = await sut.exportingAll()
        try #require(ids.ids[.adventure] != nil)
        #expect(ids.ids[.adventure]!.contains(item!.id))
        #expect(!ids.ids[.adventure]!.contains(deleted!.id))
        #expect(ids.ids[.adventure]!.count == 1)
    }

    @Test func exporting() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)

        let sut = await root.exportController

        let itemId = await root.itemController.addNew(type: .item)

        let newId = await root.itemController.addNew(type: .item)
        let url = await root.itemController.itemOrEmpty(for: newId).url(linkNumber: 0)
        let entry = AdventureEntryModel(id: UUID(), name: "Nothing", content: "\(url)")
        await root.itemController.itemOrEmpty(for: itemId).entries.append(entry)

        var ids = await sut.exporting(itemIds: ItemModuleIds(ids: Set(arrayLiteral: itemId), module: .adventure))
        var adventureIds = ids.ids[.adventure]
        try #require(adventureIds != nil)
        #expect(adventureIds!.count == 2)
        #expect(adventureIds!.contains(itemId))
        #expect(adventureIds!.contains(newId))

        let notConnected = await root.itemController.addNew(type: .item)
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
