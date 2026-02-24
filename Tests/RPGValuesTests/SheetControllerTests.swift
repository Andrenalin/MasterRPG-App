// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import RPGResourcesDebug
import Testing

@testable import CharacterRPG

struct SheetControllerTests {
    @Test func characterSheet() async throws {
        let root = try await MockRoot.importTestData()
        
        let sut = await SheetController(itemController: root.itemController, linkController: root.linkController)
        let itemId = await root.itemController.itemDataModel.items.first
        try #require(itemId != nil)
        let model = await sut.sheet(for: itemId!, entryId: nil)
        
        #expect(model.name == "Adalbert Unheil")
    }
}
#endif
