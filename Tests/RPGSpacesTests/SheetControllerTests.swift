// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import Foundation
import Testing

@testable import SpaceRPG

@MainActor
struct SheetControllerTests {
    @Test func spaceSheetBasic() async throws {
        let root = SpaceRootModel.testRoot()

        let sut = SheetController(itemController: root.itemController)

        let itemId = Foundation.UUID()
        let spaceModel = SpaceModel(
            id: itemId,
            name: "Test Space",
            description: "Empty space",
            displayState: 0
        )
        root.itemController.itemDataModel.itemData[itemId] = spaceModel

        let model = sut.sheet(root: RootManager(anyRoot: root), itemId: itemId, destination: Optional<ItemRowModel>.none, level: 0, isShown: true)

        #expect(model.name == "Test Space")
        #expect(model.description == "Empty space")
        #expect(model.isShown == true)
        #expect(model.level == 0)
        #expect(model.sheetType == SheetModelType.space)
        #expect(model.source.itemId == itemId)
        #expect(model.source.typeId == NetworkModules.space)
    }

    @Test func spaceSheetWithDestination() async throws {
        let root = SpaceRootModel.testRoot()

        let sut = SheetController(itemController: root.itemController)

        let itemId = Foundation.UUID()
        let spaceModel = SpaceModel(id: itemId, name: "Test", displayState: 0)
        root.itemController.itemDataModel.itemData[itemId] = spaceModel

        let destination = ItemRowModel(itemId: Foundation.UUID(), typeId: NetworkModules.adventure)
        let model = sut.sheet(root: RootManager(anyRoot: root), itemId: itemId, destination: destination, level: 1, isShown: false)

        #expect(model.destination.itemId == destination.itemId)
        #expect(model.level == 1)
        #expect(model.isShown == false)
    }

    @Test func spaceSheetNoEntries() async throws {
        let root = SpaceRootModel.testRoot()

        let sut = SheetController(itemController: root.itemController)

        let itemId = Foundation.UUID()
        let spaceModel = SpaceModel(id: itemId, name: "Test", displayState: 0)
        root.itemController.itemDataModel.itemData[itemId] = spaceModel

        let model = sut.sheet(root: RootManager(anyRoot: root), itemId: itemId, destination: Optional<ItemRowModel>.none, level: 0, isShown: true)

        // Space sheets have no sub-entries
        #expect(model.entries.isEmpty)
        #expect(model.inlineEntries.isEmpty)
    }
}
#endif
