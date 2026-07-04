// @copyright André Trettin


import CoreRPG
import Foundation
import Testing

@testable import AudioRPG

@MainActor
struct ExportControllerTests {
    @Test func exportingAll() async throws {
        let root = await AudioRootModel.testRoot()
        await root.itemController.resetData()

        let sut = await root.exportController

        var ids = await sut.exportingAll()
        try #require(ids.ids[.audio] != nil)
        #expect(ids.ids[.audio]!.isEmpty)

        let itemId = await root.itemController.addNew(type: .item)
        ids = await sut.exportingAll()
        try #require(ids.ids[.audio] != nil)
        #expect(ids.ids[.audio]! == [itemId])

        let newId = await root.itemController.addNew(type: .item)
        let entry = AudioEntryModel(id: UUID(), audioId: newId)
        await root.itemController.itemOrEmpty(for: itemId).entries.append(entry)

        ids = await sut.exportingAll()
        try #require(ids.ids[.audio] != nil)
        #expect(ids.ids[.audio]!.count == 2)
    }

    @Test func exporting() async throws {
        let root = await AudioRootModel.testRoot()
        await root.itemController.resetData()

        let sut = await root.exportController

        let itemId = await root.itemController.addNew(type: .item)

        let newId = await root.itemController.addNew(type: .item)
        let entry = AudioEntryModel(id: UUID(), audioId: newId)
        await root.itemController.itemOrEmpty(for: itemId).entries.append(entry)

        var ids = await sut.exporting(itemIds: ItemModuleIds(ids: Set(arrayLiteral: itemId), module: .audio))
        var audioIds = ids.ids[.audio]
        try #require(audioIds != nil)
        #expect(audioIds!.count == 2)
        #expect(audioIds!.contains(itemId))
        #expect(audioIds!.contains(newId))

        let notConnected = await root.itemController.addNew(type: .item)
        ids = await sut.exporting(itemIds: ItemModuleIds(ids: Set([itemId]), module: .audio))
        audioIds = ids.ids[.audio]
        try #require(audioIds != nil)
        #expect(audioIds!.count == 2)
        #expect(audioIds!.contains(itemId))
        #expect(audioIds!.contains(newId))
        #expect(!audioIds!.contains(notConnected))
    }
}
