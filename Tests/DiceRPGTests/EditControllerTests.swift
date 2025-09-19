// @copyright André Trettin

import Testing
import SwiftData
@testable import CoreRPG
@testable import DiceRPG
@testable import RPGResources
import Foundation

struct EditControllerTests {

    @MainActor
    func makeRoot() throws -> DiceRootModel {
        let modelContainer = try ModelContainer(for: ItemDataModel.self, DiceDataModel.self, DieDataModel.self, LinkDataModel.self, TagDataModel.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return DiceRootModel(modelContext: modelContainer.mainContext)
    }
    
    @MainActor
    func models(in root: DiceRootModel) -> [ItemDataModel] {
        let ids = root.itemController.allItemIds(module: .dice)
        return ids.compactMap {
            ItemDataModel.model(modelContext: root.modelContext, id: $0)
        }
    }
    
    @Test
    @MainActor
    func testDeleteItem() throws {
        // Given: A root model with an item and associated dice data
        let root = try makeRoot()
        let modelContext = root.modelContext
        
        // Create an ItemDataModel
        let testItemId = UUID()
        let itemModel = ItemDataModel(
            id: testItemId,
            module: .dice,
            name: "Test Dice Item",
            information: "Test description",
            category: .rules,
            tags: ["test"]
        )
        modelContext.insert(itemModel)
        try modelContext.save()
        
        // Ensure DiceDataModel is created by accessing it
        let diceModel = root.itemController.model(for: testItemId)
        #expect(diceModel != nil, "DiceDataModel should be created")
        #expect(diceModel?.itemId == testItemId, "DiceDataModel should have correct itemId")
        
        // Verify both models exist before deletion
        let itemExists = ItemDataModel.model(modelContext: modelContext, id: testItemId) != nil
        #expect(itemExists, "ItemDataModel should exist before deletion")
        
        let diceExists = root.itemController.model(for: testItemId) != nil
        #expect(diceExists, "DiceDataModel should exist before deletion")
        
        // When: We delete the item using EditController
        root.editController.delete(item: itemModel)
        
        // Then: Both ItemDataModel and DiceDataModel should be deleted
        let itemExistsAfter = ItemDataModel.model(modelContext: modelContext, id: testItemId) != nil
        #expect(!itemExistsAfter, "ItemDataModel should be deleted")
        
        // Verify DiceDataModel is also deleted by checking if fetch returns nil/empty
        let predicate = #Predicate<DiceDataModel> { $0.itemId == testItemId }
        let fetchDesc = FetchDescriptor<DiceDataModel>(predicate: predicate)
        let remainingDiceModels = try modelContext.fetch(fetchDesc)
        #expect(remainingDiceModels.isEmpty, "DiceDataModel should be deleted")
    }
    
    @Test
    @MainActor
    func testDeleteNonExistentItem() throws {
        // Given: A root model
        let root = try makeRoot()
        
        // Create a non-existent ItemDataModel (not inserted into context)
        let nonExistentItemId = UUID()
        let itemModel = ItemDataModel(
            id: nonExistentItemId,
            module: .dice,
            name: "Non-existent Item",
            information: "This item was never saved",
            category: .rules,
            tags: []
        )
        
        // When: We try to delete the non-existent item
        // Then: It should not crash and handle gracefully
        #expect(throws: Never.self) {
            root.editController.delete(item: itemModel)
        }
    }
    
    @Test
    @MainActor
    func testDeleteItemWithDiceData() throws {
        // Given: A root model with an item and dice data with actual dice
        let root = try makeRoot()
        let modelContext = root.modelContext
        
        // Create an ItemDataModel
        let testItemId = UUID()
        let itemModel = ItemDataModel(
            id: testItemId,
            module: .dice,
            name: "Test Dice with Data",
            information: "Test dice configuration",
            category: .rules,
            tags: ["dice", "test"]
        )
        modelContext.insert(itemModel)
        try modelContext.save()
        
        // Get the DiceDataModel and add some dice to it
        let diceModel = root.itemController.model(for: testItemId)
        #expect(diceModel != nil, "DiceDataModel should be created")
        
        // Add some dice using the EditController's add method
        let die1 = DieDataModel(id: UUID(), index: 0, die: .six)
        let die2 = DieDataModel(id: UUID(), index: 1, die: .twenty)
        
        root.editController.add(die: die1, to: diceModel!)
        root.editController.add(die: die2, to: diceModel!)
        
        // Verify dice were added
        #expect(diceModel!.dice.count == 2, "Should have 2 dice")
        
        // Verify all models exist before deletion
        #expect(ItemDataModel.model(modelContext: modelContext, id: testItemId) != nil, "ItemDataModel should exist")
        
        let diceExistsPredicate = #Predicate<DiceDataModel> { $0.itemId == testItemId }
        let diceFetchDesc = FetchDescriptor<DiceDataModel>(predicate: diceExistsPredicate)
        let diceModelsBeforeDelete = try modelContext.fetch(diceFetchDesc)
        #expect(diceModelsBeforeDelete.count == 1, "Should have 1 DiceDataModel")
        
        let dieExistsPredicate = #Predicate<DieDataModel> { $0.parent?.itemId == testItemId }
        let dieFetchDesc = FetchDescriptor<DieDataModel>(predicate: dieExistsPredicate)
        let dieModelsBeforeDelete = try modelContext.fetch(dieFetchDesc)
        #expect(dieModelsBeforeDelete.count == 2, "Should have 2 DieDataModel instances")
        
        // When: We delete the item using EditController
        root.editController.delete(item: itemModel)
        
        // Then: All related models should be deleted (cascade deletion)
        #expect(ItemDataModel.model(modelContext: modelContext, id: testItemId) == nil, "ItemDataModel should be deleted")
        
        let diceModelsAfterDelete = try modelContext.fetch(diceFetchDesc)
        #expect(diceModelsAfterDelete.isEmpty, "DiceDataModel should be deleted")
        
        let dieModelsAfterDelete = try modelContext.fetch(dieFetchDesc)
        #expect(dieModelsAfterDelete.isEmpty, "DieDataModel instances should be cascade deleted")
    }
    
    @Test
    @MainActor
    func testDuplicateItemWithDiceData() throws {
        // Given: A root model with a configured dice item
        let root = try makeRoot()
        let modelContext = root.modelContext
        
        // Create an original ItemDataModel
        let originalItemId = UUID()
        let originalItemModel = ItemDataModel(
            id: originalItemId,
            module: .dice,
            name: "Original Dice Configuration",
            information: "A complex dice setup",
            category: .rules,
            tags: ["original", "complex"]
        )
        modelContext.insert(originalItemModel)
        try modelContext.save()
        
        // Get the DiceDataModel and configure it with dice and settings
        let originalDiceModel = root.itemController.model(for: originalItemId)
        #expect(originalDiceModel != nil, "Original DiceDataModel should be created")
        
        // Configure the dice model with complex settings
        originalDiceModel!.sumUp = false
        originalDiceModel!.modifier = 5.5
        originalDiceModel!.percentDice = true
        originalDiceModel!.compareValue = 75.0
        originalDiceModel!.compareOption = .lowerEqual
        originalDiceModel!.coupOnlyOnFirstDie = true
        originalDiceModel!.fumbleOnlyOnFirstDie = false
        originalDiceModel!.reorderDice = true
        originalDiceModel!.addDiceEvery = 3
        
        // Add coup and fumble values
        originalDiceModel!.coupValues = [.result(95), .diceValue(6)]
        originalDiceModel!.fumbleValues = [.result(5), .diceValue(1)]
        
        // Add reroll options
        originalDiceModel!.rerollOptions = [
            DiceDataModel.RerollOption(number: 1, value: 2, maxDiceValue: true),
            DiceDataModel.RerollOption(number: 6, value: 1, maxDiceValue: false)
        ]
        
        // Add some dice using EditController
        let die1 = DieDataModel(id: UUID(), index: 0, die: .ten, color: "red")
        let die2 = DieDataModel(id: UUID(), index: 1, die: .twenty, color: "blue") 
        let die3 = DieDataModel(id: UUID(), index: 2, die: .six, color: "green")
        
        root.editController.add(die: die1, to: originalDiceModel!)
        root.editController.add(die: die2, to: originalDiceModel!)
        root.editController.add(die: die3, to: originalDiceModel!)
        
        // Verify original setup
        #expect(originalDiceModel!.dice.count == 3, "Original should have 3 dice")
        
        // Count original models
        let originalItemCount = try modelContext.fetch(FetchDescriptor<ItemDataModel>()).count
        let originalDiceCount = try modelContext.fetch(FetchDescriptor<DiceDataModel>()).count
        let originalDieCount = try modelContext.fetch(FetchDescriptor<DieDataModel>()).count
        
        // When: We duplicate the item using EditController
        root.editController.duplicate(item: originalItemModel)
        
        // Then: We should have duplicated both ItemDataModel and DiceDataModel
        let allItemsAfterDuplicate = try modelContext.fetch(FetchDescriptor<ItemDataModel>())
        let allDiceAfterDuplicate = try modelContext.fetch(FetchDescriptor<DiceDataModel>())
        let allDieAfterDuplicate = try modelContext.fetch(FetchDescriptor<DieDataModel>())
        
        #expect(allItemsAfterDuplicate.count == originalItemCount + 1, "Should have one additional ItemDataModel")
        #expect(allDiceAfterDuplicate.count == originalDiceCount + 1, "Should have one additional DiceDataModel")
        #expect(allDieAfterDuplicate.count == originalDieCount + 3, "Should have 3 additional DieDataModel instances")
        
        // Find the duplicated ItemDataModel (should be the one with different ID)
        let duplicatedItemModel = allItemsAfterDuplicate.first { $0.id != originalItemId }
        #expect(duplicatedItemModel != nil, "Duplicated ItemDataModel should exist")
        
        // Verify duplicated ItemDataModel properties
        #expect(duplicatedItemModel!.name == originalItemModel.name, "Name should be duplicated")
        #expect(duplicatedItemModel!.information == originalItemModel.information, "Information should be duplicated")
        #expect(duplicatedItemModel!.category == originalItemModel.category, "Category should be duplicated")
        #expect(duplicatedItemModel!.tags == originalItemModel.tags, "Tags should be duplicated")
        #expect(duplicatedItemModel!.module == originalItemModel.module, "Module should be duplicated")
        
        // Get the duplicated DiceDataModel
        let duplicatedDiceModel = root.itemController.model(for: duplicatedItemModel!.id)
        #expect(duplicatedDiceModel != nil, "Duplicated DiceDataModel should exist")
        
        // Verify all DiceDataModel properties were duplicated correctly
        #expect(duplicatedDiceModel!.sumUp == originalDiceModel!.sumUp, "sumUp should be duplicated")
        #expect(duplicatedDiceModel!.modifier == originalDiceModel!.modifier, "modifier should be duplicated")
        #expect(duplicatedDiceModel!.percentDice == originalDiceModel!.percentDice, "percentDice should be duplicated")
        #expect(duplicatedDiceModel!.compareValue == originalDiceModel!.compareValue, "compareValue should be duplicated")
        #expect(duplicatedDiceModel!.compareOption == originalDiceModel!.compareOption, "compareOption should be duplicated")
        #expect(duplicatedDiceModel!.coupOnlyOnFirstDie == originalDiceModel!.coupOnlyOnFirstDie, "coupOnlyOnFirstDie should be duplicated")
        #expect(duplicatedDiceModel!.fumbleOnlyOnFirstDie == originalDiceModel!.fumbleOnlyOnFirstDie, "fumbleOnlyOnFirstDie should be duplicated")
        #expect(duplicatedDiceModel!.reorderDice == originalDiceModel!.reorderDice, "reorderDice should be duplicated")
        #expect(duplicatedDiceModel!.addDiceEvery == originalDiceModel!.addDiceEvery, "addDiceEvery should be duplicated")
        
        // Verify complex arrays were duplicated
        #expect(duplicatedDiceModel!.coupValues.count == originalDiceModel!.coupValues.count, "Coup values count should match")
        #expect(duplicatedDiceModel!.fumbleValues.count == originalDiceModel!.fumbleValues.count, "Fumble values count should match")
        #expect(duplicatedDiceModel!.rerollOptions.count == originalDiceModel!.rerollOptions.count, "Reroll options count should match")
        
        // Verify dice were duplicated correctly
        #expect(duplicatedDiceModel!.dice.count == 3, "Duplicated should have 3 dice")
        
        let originalDice = originalDiceModel!.dice.sorted { $0.index < $1.index }
        let duplicatedDice = duplicatedDiceModel!.dice.sorted { $0.index < $1.index }
        
        for (index, (original, duplicated)) in zip(originalDice, duplicatedDice).enumerated() {
            #expect(duplicated.id != original.id, "Dice \(index) should have different ID")
            #expect(duplicated.die == original.die, "Dice \(index) die type should match")
            #expect(duplicated.color == original.color, "Dice \(index) color should match")
            #expect(duplicated.index == original.index, "Dice \(index) index should match")
        }
        
        // Verify the itemId relationship is correct
        #expect(duplicatedDiceModel!.itemId == duplicatedItemModel!.id, "DiceDataModel should reference correct ItemDataModel ID")
    }

}
