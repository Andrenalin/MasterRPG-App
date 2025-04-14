// @copyright André Trettin

#if canImport(Testing)
import AndrenalinKit
import Foundation
import RPGDie
import Testing

@testable import RPGTables

struct ExportControllerTests {
    @Test func exportingAll() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)

        let sut = root.exportController

        var ids = await sut.exportingAll()
        try #require(ids.ids[.table] != nil)
        #expect(ids.ids[.table]!.isEmpty)

        let itemId = await root.itemController.addNew(type: nil).itemId
        ids = await sut.exportingAll()
        try #require(ids.ids[.table] != nil)
        #expect(ids.ids[.table]! == [itemId])

        let newId = await root.itemController.addNew(type: nil).itemId
        let entry = await TableEntryModel(id: UUID(), name: "Nothing", content: root.linkController.generateLink(itemId: newId))
        await root.itemController.itemOrEmpty(for: itemId).entries.append(entry)

        ids = await sut.exportingAll()

        try #require(ids.ids[.table] != nil)
        #expect(ids.ids[.table]!.count == 2)
    }

    @Test func exporting() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)

        let sut = root.exportController

        let itemId = await root.itemController.addNew(type: nil).itemId

        let newId = await root.itemController.addNew(type: nil).itemId
        let url = await root.itemController.itemOrEmpty(for: newId).url(linkNumber: 0)

        let entry = TableEntryModel(id: UUID(), name: "Nothing", content: "Some text: \(url)")
        await root.itemController.itemOrEmpty(for: itemId).entries.append(entry)

        var ids = await sut.exporting(itemIds: ItemModuleIds(ids: Set(arrayLiteral: itemId), module: .table))
        var tableIds = ids.ids[.table]
        try #require(tableIds != nil)
        #expect(tableIds!.count == 2)
        #expect(tableIds!.contains(itemId))
        #expect(tableIds!.contains(newId))

        let notConnected = await root.itemController.addNew(type: nil).itemId
        ids = await sut.exporting(itemIds: ItemModuleIds(ids: Set([itemId]), module: .table))
        tableIds = ids.ids[.table]
        try #require(tableIds != nil)
        #expect(tableIds!.count == 2)
        #expect(tableIds!.contains(itemId))
        #expect(tableIds!.contains(newId))
        #expect(!tableIds!.contains(notConnected))
    }
}
#endif
