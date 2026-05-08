// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import Foundation
import Testing

@testable import DiceRPG

@MainActor
struct SheetControllerTests {
    @Test func diceSheetBasic() async throws {
        let root = DiceRootModel.testRoot()

        let sut = SheetController(itemController: root.itemController)

        // Create test dice item
        let itemId = Foundation.UUID()
        let diceModel = DiceModel(id: itemId, name: "Test Dice", description: "1d6", category: .scenario, displayState: 0, dice: [])
        root.itemController.itemDataModel.itemData[itemId] = diceModel

        let model = sut.sheet(root: RootManager(anyRoot: root), itemId: itemId, destination: Optional<ItemRowModel>.none, level: 0, isShown: true, isEditor: false)

        #expect(model.name == "Test Dice")
        #expect(model.description == "1d6")
        #expect(model.isShown == true)
        #expect(model.level == 0)
        #expect(model.sheetType == SheetModelType.dice)
        #expect(model.source.itemId == itemId)
        #expect(model.source.typeId == NetworkModules.dice)
    }

    @Test func diceSheetWithDestination() async throws {
        let root = DiceRootModel.testRoot()

        let sut = SheetController(itemController: root.itemController)

        let itemId = Foundation.UUID()
        let diceModel = DiceModel(id: itemId, name: "Test", description: "", category: .scenario, displayState: 0, dice: [])
        root.itemController.itemDataModel.itemData[itemId] = diceModel

        let destination = ItemRowModel(itemId: Foundation.UUID(), typeId: NetworkModules.table)
        let model = sut.sheet(root: RootManager(anyRoot: root), itemId: itemId, destination: destination, level: 2, isShown: false, isEditor: false)

        #expect(model.destination.itemId == destination.itemId)
        #expect(model.level == 2)
        #expect(model.isShown == false)
    }

    @Test func diceSheetNoEntries() async throws {
        let root = DiceRootModel.testRoot()

        let sut = SheetController(itemController: root.itemController)

        let itemId = Foundation.UUID()
        let diceModel = DiceModel(id: itemId, name: "Test", description: "", category: .scenario, displayState: 0, dice: [])
        root.itemController.itemDataModel.itemData[itemId] = diceModel

        let model = sut.sheet(root: RootManager(anyRoot: root), itemId: itemId, destination: Optional<ItemRowModel>.none, level: 0, isShown: true, isEditor: false)

        // Dice sheets have no sub-entries
        #expect(model.entries.isEmpty)
        #expect(model.inlineEntries.isEmpty)
    }
}
#endif
