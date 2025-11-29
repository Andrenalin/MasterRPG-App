// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import DiceRPG
import Foundation
import PdfRPG
import PhotoRPG
import TableRPG
import RPGResourcesDebug
import Testing

@testable import CharacterRPG

struct ListControllerTests {
    @Test func setSelectedItem() async throws {
        let root = try await MockRoot.importTestData()
        let sut = await root.listController(tabId: UUID())

        let originalId = await root.itemController.itemDataModel.items[0]
        let item = await root.itemController.itemOrEmpty(for: originalId)
        #expect(item.entries.count == 11)
        await sut.update(models: root.itemController.itemDataModel.items.map { ItemRowModel(itemId: $0, typeId: .value) } )
        await sut.setSelectedItem(model: ItemRowModel(itemId: originalId, typeId: .value))
        
        await #expect(sut.model.selectedItem?.model == ItemRowModel(itemId: originalId, typeId: .value))
        await #expect(sut.model.selectedItems.count == 1)
        await #expect(sut.model.selectedItems[0].model == ItemRowModel(itemId: originalId, typeId: .value))
    }
}
#endif
