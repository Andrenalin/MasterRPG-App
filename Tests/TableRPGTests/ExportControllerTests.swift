// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import Foundation
import DiceRPG
import PdfRPG
import Testing

@testable import TableRPG

@MainActor
struct ExportControllerTests {
    @Test func exportingAll() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)

        let sut = root.exportController

        var ids = sut.exportingAll()
        try #require(ids.ids[.table] != nil)
        #expect(ids.ids[.table]!.isEmpty)

        let itemId = await root.itemController.addNew(type: .item)
        ids = sut.exportingAll()
        try #require(ids.ids[.table] != nil)
        #expect(ids.ids[.table]! == [itemId])

        let newId = await root.itemController.addNew(type: .item)
        let entry = TableEntryModel(id: UUID(), name: "Nothing", content: root.linkController.generateLink(itemId: newId))
        root.itemController.itemOrEmpty(for: itemId).entries.append(entry)

        ids = sut.exportingAll()

        try #require(ids.ids[.table] != nil)
        #expect(ids.ids[.table]!.count == 2)
    }

    @Test func exportingAllAfterDeletion() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)

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
        try #require(ids.ids[.table] != nil)
        #expect(ids.ids[.table]!.contains(item!.id))
        #expect(!ids.ids[.table]!.contains(deleted!.id))
        #expect(ids.ids[.table]!.count == 1)
    }

    @Test func exporting() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)

        let sut = root.exportController

        let itemId = await root.itemController.addNew(type: .item)

        let newId = await root.itemController.addNew(type: .item)
        let url = root.itemController.itemOrEmpty(for: newId).url(linkNumber: 0)

        let entry = TableEntryModel(id: UUID(), name: "Nothing", content: "Some text: \(url)")
        root.itemController.itemOrEmpty(for: itemId).entries.append(entry)

        var ids = sut.exporting(itemIds: ItemModuleIds(ids: Set(arrayLiteral: itemId), module: .table))
        var tableIds = ids.ids[.table]
        try #require(tableIds != nil)
        #expect(tableIds!.count == 2)
        #expect(tableIds!.contains(itemId))
        #expect(tableIds!.contains(newId))

        let notConnected = await root.itemController.addNew(type: .item)
        ids = sut.exporting(itemIds: ItemModuleIds(ids: Set([itemId]), module: .table))
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

        let sut = root.exportController
        let edit = root.editController

        let folder = await edit.addNew(type: .folder)
        try #require(folder != nil)
        let folderId = folder!.id

        let itemId = await root.itemController.addNew(type: .item)
        edit.addItem(itemId: itemId, parentId: folderId)

        let ids = sut.exporting(itemIds: ItemModuleIds(ids: Set([itemId]), module: .table))
        let valueIds = ids.ids[.table]
        try #require(valueIds != nil)
        #expect(valueIds!.contains(itemId))
        #expect(valueIds!.contains(folderId))
        #expect(ids.partialIds[.value] == nil)
    }

    @Test func exportingItemInFolderExcludesSiblings() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)

        let sut = root.exportController
        let edit = root.editController

        let folder = await edit.addNew(type: .folder)
        try #require(folder != nil)
        let folderId = folder!.id

        let itemId = await root.itemController.addNew(type: .item)
        let siblingId = await root.itemController.addNew(type: .item)
        edit.addItem(itemId: itemId, parentId: folderId)
        edit.addItem(itemId: siblingId, parentId: folderId)

        let ids = sut.exporting(itemIds: ItemModuleIds(ids: Set([itemId]), module: .table))
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

        let sut = root.exportController
        let edit = root.editController

        let folder = await edit.addNew(type: .folder)
        try #require(folder != nil)
        let folderId = folder!.id

        let otherItemId = await root.itemController.addNew(type: .item)
        let itemId = await root.itemController.addNew(type: .item)
        let siblingId = await root.itemController.addNew(type: .item)
        edit.addItem(itemId: itemId, parentId: folderId)
        edit.addItem(itemId: siblingId, parentId: folderId)

        let ids = sut.exporting(itemIds: ItemModuleIds(ids: Set([itemId, folderId]), module: .table))
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
        let edit = root.editController
        let sut = root.exportController

        let diceId = await root.diceRoot.itemControllable.addNew(type: .rules)
        let itemId = await root.itemController.addNew(type: .item)
        edit.add(diceId: diceId, itemId: itemId)

        let ids = sut.exporting(itemIds: ItemModuleIds(ids: Set([itemId]), module: .table))
        let tableIds = ids.ids[.table]
        try #require(tableIds != nil)
        #expect(tableIds!.contains(itemId))
        #expect(ids.ids[.dice]?.contains(diceId) == true)
    }

    @Test("Exporting all Tables includes PDF dependencies")
    func exportingAllIncludesPdfs() async throws {
        // Given
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let pdfId = await root.pdfRoot.itemControllable.addNew(type: .item)

        // When
        let ids = root.exportController.exportingAll()

        // Then
        let pdfIds = try #require(ids.ids[.pdf])
        #expect(pdfIds == [pdfId])
    }

    @Test("Exporting a Table includes its linked PDF only")
    func exportingTableWithPdfLinkExportsPdf() async throws {
        // Given
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let linkedPdfId = await root.pdfRoot.itemControllable.addNew(type: .item)
        let unrelatedPdfId = await root.pdfRoot.itemControllable.addNew(type: .item)
        let tableId = await root.itemController.addNew(type: .item)
        let pdfLink = root.pdfRoot.linkControllable.generateLink(
            linkNumber: 0,
            itemId: linkedPdfId,
            entryId: nil
        )
        root.itemController.itemOrEmpty(for: tableId).entries.append(
            TableEntryModel(id: UUID(), name: "PDF", content: pdfLink)
        )

        // When
        let ids = root.exportController.exporting(
            itemIds: ItemModuleIds(ids: Set([tableId]), module: .table)
        )

        // Then
        let tableIds = try #require(ids.ids[.table])
        let pdfIds = try #require(ids.ids[.pdf])
        #expect(tableIds == [tableId])
        #expect(pdfIds.contains(linkedPdfId))
        #expect(!pdfIds.contains(unrelatedPdfId))
    }

    @Test("PDF links in recursively linked Tables are exported")
    func exportingLinkedTableIncludesItsPdf() async throws {
        // Given
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let pdfId = await root.pdfRoot.itemControllable.addNew(type: .item)
        let rootTableId = await root.itemController.addNew(type: .item)
        let linkedTableId = await root.itemController.addNew(type: .item)
        let tableLink = root.linkController.generateLink(itemId: linkedTableId)
        let pdfLink = root.pdfRoot.linkControllable.generateLink(
            linkNumber: 0,
            itemId: pdfId,
            entryId: nil
        )
        root.itemController.itemOrEmpty(for: rootTableId).entries.append(
            TableEntryModel(id: UUID(), name: "Linked Table", content: tableLink)
        )
        root.itemController.itemOrEmpty(for: linkedTableId).entries.append(
            TableEntryModel(id: UUID(), name: "Linked PDF", content: pdfLink)
        )

        // When
        let ids = root.exportController.exporting(
            itemIds: ItemModuleIds(ids: Set([rootTableId]), module: .table)
        )

        // Then
        let tableIds = try #require(ids.ids[.table])
        let pdfIds = try #require(ids.ids[.pdf])
        #expect(tableIds.contains(rootTableId))
        #expect(tableIds.contains(linkedTableId))
        #expect(pdfIds.contains(pdfId))
    }

}
#endif
