// @copyright André Trettin

#if canImport(Testing)
import AndrenalinKit
import Foundation
import RPGDie
import RPGPdfs
import PhotoRPG
import RPGResourcesDebug
import RPGTables
import Testing

@testable import RPGValues

struct ExportControllerTests {
    @Test func exportingAll() async throws {
        let root = try await MockRoot.importTestData()
        let sut = root.exportController

        var ids = await sut.exportingAll()
        try #require(ids.ids[.value] != nil)
        #expect(ids.ids[.value]!.count == 15)

        let itemId = await root.itemController.addNew(type: nil).itemId
        ids = await sut.exportingAll()
        try #require(ids.ids[.value] != nil)
        #expect(ids.ids[.value]!.contains(itemId))

        let newId = await root.itemController.addNew(type: nil).itemId
        let entry = await ValueEntryModel(id: UUID(), name: "Nothing", type: .text, value: root.linkController.generateLink(itemId: newId))
        await root.itemController.itemOrEmpty(for: itemId).entries.append(entry)

        ids = await sut.exportingAll()
        try #require(ids.ids[.value] != nil)
        #expect(ids.ids[.value]!.count == 17)
    }

    @Test func exporting() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)

        let sut = root.exportController

        let itemId = await root.itemController.addNew(type: nil).itemId

        let newId = await root.itemController.addNew(type: nil).itemId
        let url = await root.itemController.itemOrEmpty(for: newId).url(linkNumber: 0)
        let entry = ValueEntryModel(id: UUID(), name: "Nothing", type: .text, value: "\(url)")
        await root.itemController.itemOrEmpty(for: itemId).entries.append(entry)

        var ids = await sut.exporting(itemIds: ItemModuleIds(ids: Set(arrayLiteral: itemId), module: .value))
        var valueIds = ids.ids[.value]
        try #require(valueIds != nil)
        #expect(valueIds!.count == 2)
        #expect(valueIds!.contains(itemId))
        #expect(valueIds!.contains(newId))

        let notConnected = await root.itemController.addNew(type: nil).itemId
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
