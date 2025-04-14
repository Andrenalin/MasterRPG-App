// @copyright André Trettin

#if canImport(Testing)
import AndrenalinKit
import RPGDie
import Foundation
import RPGAudios
import RPGMaps
import RPGPdfs
import RPGSpaces
import RPGValues
import RPGResourcesDebug
import Testing
import RPGWeathers

@testable import RPGAdventures
@testable import RPGPhotos
@testable import RPGTables

struct ItemControllerTests {
    @Test func itemRegisterLinks() async throws {
        let root = try await MockRoot.importTestData()
        let sut = root.itemController

        await #expect(sut.itemDataModel.items.count == 3)
        await #expect(root.photoRoot.itemController.itemDataModel.items.count == 27)
        let model = await sut.itemOrEmpty(for: sut.itemDataModel.items[0])
        #expect(model.name == "1. Kinder der Ratten")
        let photoId = model.photoId
        #expect(nil != photoId)
        await #expect(root.photoRoot.itemController.itemOrEmpty(for: photoId!).name == "Ratten")
        let isUsed = await sut.linkRegisterControllable.isUsed(link: ItemRowModel(itemId: photoId!, typeId: .photo))
        #expect(isUsed)

        let effectedLinks = await sut.linkRegisterControllable.used(for: ItemRowModel(itemId: photoId!, typeId: .photo))
        #expect(effectedLinks.count == 1)
        #expect(effectedLinks[0].module == .adventure)
        #expect(effectedLinks[0].name == model.name)
    }

    @Test func itemRegisterLinksIsUsedReturnsAlsoEntries() async throws {
        let root = try await MockRoot.importTestData()
        let sut = root.itemController

        await #expect(sut.itemDataModel.items.count == 3)
        await #expect(root.tableRoot.itemController.itemDataModel.items.count == 53)

        var tableId: UUID? = nil
        for itemId in await root.tableRoot.itemController.itemDataModel.items {
            if await root.tableRoot.itemController.itemOrEmpty(for: itemId).name == "Talente" {
                tableId = itemId
                break
            }
        }
        try #require(nil != tableId)
        let isUsed = await sut.linkRegisterControllable.isUsed(link: ItemRowModel(itemId: tableId!, typeId: .table))
        #expect(isUsed)
        let effectedLinks = await sut.linkRegisterControllable.used(for: ItemRowModel(itemId: tableId!, typeId: .table))
        #expect(effectedLinks.count == 107)
    }
}
#endif
