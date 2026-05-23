// @copyright André Trettin

import CoreRPG
import DiceRPG
import Foundation
import AudioRPG
import MapRPG
import PdfRPG
import SpaceRPG
import CharacterRPG
import RPGResourcesDebug
import Testing
import WeatherRPG

@testable import AdventureRPG
@testable import PhotoRPG
@testable import TableRPG

struct ItemControllerTests {
    @Test func itemRegisterLinks() async throws {
        let root = try await MockRoot.importTestData()
        let sut = await root.itemController

        await #expect(sut.itemDataModel.items.count == 3)
        await #expect(root.photoRoot.itemController.itemDataModel.items.count == 32)
        let model = await sut.itemOrEmpty(for: sut.itemDataModel.items[0])
        #expect(model.name == "1. Kinder der Ratten")
        let photoId = model.photoId
        #expect(nil != photoId)
        await #expect(root.photoRoot.itemController.itemOrEmpty(for: photoId!).name == "Ratten")
        let changed = model.copy()
        changed.name = "Updated"
        let newId = UUID()
        changed.photoId = newId
        await root.editController.save(updated: changed, message: "")
        let isUsed = await sut.linkRegisterController.isUsed(link: ItemRowModel(itemId: newId, typeId: .photo))
        #expect(isUsed)

        let effectedLinks = await sut.linkRegisterController.used(for: ItemRowModel(itemId: newId, typeId: .photo))
        try #require(effectedLinks.count == 1)
        #expect(effectedLinks[0].module == .adventure)
        #expect(effectedLinks[0].name == model.name)
    }

    @Test func itemRegisterLinksIsUsedReturnsAlsoEntries() async throws {
        let root = try await MockRoot.importTestData()
        let sut = await root.itemController

        let cc = await ConvertController(itemController: sut, editController: root.editController)
        await cc.createFoldersAndCollections(reportModel: ValidateRepairModel(), overwriteEntryCheck: true)
        
        await #expect(sut.itemDataModel.items.count == 4)
        let item = await sut.itemOrEmpty(for: sut.itemDataModel.items[0])
        try #require(item.photoId != nil)
        
        let isUsed = await sut.linkRegisterController.isUsed(link: ItemRowModel(itemId: item.photoId!, typeId: .photo))
        #expect(isUsed)
        let effectedLinks = await sut.linkRegisterController.used(for: ItemRowModel(itemId: item.photoId!, typeId: .photo))
        #expect(effectedLinks.count == 1)
    }
}
