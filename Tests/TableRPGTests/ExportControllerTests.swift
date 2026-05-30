// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import Foundation
import DiceRPG
import Testing

@testable import TableRPG

struct ExportControllerTests {
    @Test func exportingAll() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)

        let sut = await root.exportController

        var ids = await sut.exportingAll()
        try #require(ids.ids[.table] != nil)
        #expect(ids.ids[.table]!.isEmpty)

        let itemId = await root.itemController.addNew(type: .item)
        ids = await sut.exportingAll()
        try #require(ids.ids[.table] != nil)
        #expect(ids.ids[.table]! == [itemId])

        let newId = await root.itemController.addNew(type: .item)
        let entry = await TableEntryModel(id: UUID(), name: "Nothing", content: root.linkController.generateLink(itemId: newId))
        await root.itemController.itemOrEmpty(for: itemId).entries.append(entry)

        ids = await sut.exportingAll()

        try #require(ids.ids[.table] != nil)
        #expect(ids.ids[.table]!.count == 2)
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
        try #require(ids.ids[.table] != nil)
        #expect(ids.ids[.table]!.contains(item!.id))
        #expect(!ids.ids[.table]!.contains(deleted!.id))
        #expect(ids.ids[.table]!.count == 1)
    }

    @Test func exporting() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)

        let sut = await root.exportController

        let itemId = await root.itemController.addNew(type: .item)

        let newId = await root.itemController.addNew(type: .item)
        let url = await root.itemController.itemOrEmpty(for: newId).url(linkNumber: 0)

        let entry = TableEntryModel(id: UUID(), name: "Nothing", content: "Some text: \(url)")
        await root.itemController.itemOrEmpty(for: itemId).entries.append(entry)

        var ids = await sut.exporting(itemIds: ItemModuleIds(ids: Set(arrayLiteral: itemId), module: .table))
        var tableIds = ids.ids[.table]
        try #require(tableIds != nil)
        #expect(tableIds!.count == 2)
        #expect(tableIds!.contains(itemId))
        #expect(tableIds!.contains(newId))

        let notConnected = await root.itemController.addNew(type: .item)
        ids = await sut.exporting(itemIds: ItemModuleIds(ids: Set([itemId]), module: .table))
        tableIds = ids.ids[.table]
        try #require(tableIds != nil)
        #expect(tableIds!.count == 2)
        #expect(tableIds!.contains(itemId))
        #expect(tableIds!.contains(newId))
        #expect(!tableIds!.contains(notConnected))
    }
    
    @Test func exportingItemInFolderIncludesFolder() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)

        let sut = await root.exportController
        let edit = await root.editController

        let folder = await edit.addNew(type: .folder)
        try #require(folder != nil)
        let folderId = folder!.id

        let itemId = await root.itemController.addNew(type: .item)
        await edit.addItem(itemId: itemId, parentId: folderId)

        let ids = await sut.exporting(itemIds: ItemModuleIds(ids: Set([itemId]), module: .table))
        let valueIds = ids.ids[.table]
        try #require(valueIds != nil)
        #expect(valueIds!.contains(itemId))
        #expect(valueIds!.contains(folderId))
        #expect(ids.partialIds[.value] == nil)
    }

    @Test func exportingItemInFolderExcludesSiblings() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)

        let sut = await root.exportController
        let edit = await root.editController

        let folder = await edit.addNew(type: .folder)
        try #require(folder != nil)
        let folderId = folder!.id

        let itemId = await root.itemController.addNew(type: .item)
        let siblingId = await root.itemController.addNew(type: .item)
        await edit.addItem(itemId: itemId, parentId: folderId)
        await edit.addItem(itemId: siblingId, parentId: folderId)

        let ids = await sut.exporting(itemIds: ItemModuleIds(ids: Set([itemId]), module: .table))
        let tableIds = ids.ids[.table]
        let partialIds = ids.partialIds[.table]
        try #require(tableIds != nil)
        try #require(partialIds != nil)
        #expect(tableIds!.contains(itemId))
        #expect(!tableIds!.contains(folderId))
        #expect(ids.partialIds[.table]?.contains(folderId) == true)
        #expect(!tableIds!.contains(siblingId))
    }

    @Test func exportingItemInFolderInlcudeSiblingsIfFolderIsExported() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)

        let sut = await root.exportController
        let edit = await root.editController

        let folder = await edit.addNew(type: .folder)
        try #require(folder != nil)
        let folderId = folder!.id

        let otherItemId = await root.itemController.addNew(type: .item)
        let itemId = await root.itemController.addNew(type: .item)
        let siblingId = await root.itemController.addNew(type: .item)
        await edit.addItem(itemId: itemId, parentId: folderId)
        await edit.addItem(itemId: siblingId, parentId: folderId)

        let ids = await sut.exporting(itemIds: ItemModuleIds(ids: Set([itemId, folderId]), module: .table))
        let tableIds = ids.ids[.table]
        try #require(tableIds != nil)
        #expect(tableIds!.contains(itemId))
        #expect(tableIds!.contains(folderId))
        #expect(tableIds!.contains(siblingId))
        #expect(ids.partialIds[.value] == nil)
        #expect(!tableIds!.contains(otherItemId))
    }

    @Test func exportingTableWithDiceIdExportsDice() async throws {
        let root = try await MockRoot.importTestData()
        let edit = await root.editController
        let sut = await root.exportController

        let diceId = await root.diceRoot.itemControllable.addNew(type: .rules)
        let itemId = await root.itemController.addNew(type: .item)
        await edit.add(diceId: diceId, itemId: itemId)

        let ids = await sut.exporting(itemIds: ItemModuleIds(ids: Set([itemId]), module: .table))
        let tableIds = ids.ids[.table]
        try #require(tableIds != nil)
        #expect(tableIds!.contains(itemId))
        #expect(ids.ids[.dice]?.contains(diceId) == true)
    }

}
#endif
