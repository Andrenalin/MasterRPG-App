// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import Foundation
import DiceRPG
import PdfRPG
import PhotoRPG
import RPGResourcesDebug
import TableRPG
import Testing

@testable import CharacterRPG

struct ExportControllerTests {
    @Test func exportingAll() async throws {
        let root = try await MockRoot.importTestData()
        let sut = await root.exportController

        var ids = await sut.exportingAll()
        try #require(ids.ids[.value] != nil)
        #expect(ids.ids[.value]!.count == 15)

        let itemId = await root.itemController.addNew(type: .item)
        ids = await sut.exportingAll()
        try #require(ids.ids[.value] != nil)
        #expect(ids.ids[.value]!.contains(itemId))

        let newId = await root.itemController.addNew(type: .item)
        let entry = await ValueEntryModel(id: UUID(), name: "Nothing", type: .text, value: root.linkController.generateLink(itemId: newId))
        await root.itemController.itemOrEmpty(for: itemId).entries.append(entry)

        ids = await sut.exportingAll()
        try #require(ids.ids[.value] != nil)
        #expect(ids.ids[.value]!.count == 17)
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
        try #require(ids.ids[.value] != nil)
        #expect(ids.ids[.value]!.contains(item!.id))
        #expect(!ids.ids[.value]!.contains(deleted!.id))
        #expect(ids.ids[.value]!.count == 1)
    }

    @Test func exporting() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)

        let sut = await root.exportController

        let itemId = await root.itemController.addNew(type: .item)

        let newId = await root.itemController.addNew(type: .item)
        let url = await root.itemController.itemOrEmpty(for: newId).url(linkNumber: 0)
        let entry = ValueEntryModel(id: UUID(), name: "Nothing", type: .text, value: "\(url)")
        await root.itemController.itemOrEmpty(for: itemId).entries.append(entry)

        var ids = await sut.exporting(itemIds: ItemModuleIds(ids: Set(arrayLiteral: itemId), module: .value))
        var valueIds = ids.ids[.value]
        try #require(valueIds != nil)
        #expect(valueIds!.count == 2)
        #expect(valueIds!.contains(itemId))
        #expect(valueIds!.contains(newId))

        let notConnected = await root.itemController.addNew(type: .item)
        ids = await sut.exporting(itemIds: ItemModuleIds(ids: Set([itemId]), module: .value))
        valueIds = ids.ids[.value]
        try #require(valueIds != nil)
        #expect(valueIds!.count == 2)
        #expect(valueIds!.contains(itemId))
        #expect(valueIds!.contains(newId))
        #expect(!valueIds!.contains(notConnected))
    }
}
#endif
