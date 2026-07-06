// @copyright André Trettin

#if canImport(Testing)
import CoreData
import CoreRPG
import Foundation
import Testing

@testable import DiceRPG

@MainActor
struct DataControllerTests {
    @Test func replaceFetchUpdateAndDelete() async throws {
        let store = try PersistentTestStore(bundles: [
            CoreRPG.Resources.bundle,
            DiceRPG.Resources.bundle
        ])
        let sut = DataController(context: store.context, batchContext: store.batchContext, token: NetworkModules.dice.token)

        let itemId = UUID()
        let parentId = UUID()
        let firstEntry = ChildEntryModel(id: UUID(), childId: UUID())
        let secondEntry = ChildEntryModel(id: UUID(), childId: UUID())
        let original = DiceModel(
            id: itemId,
            name: "Attack",
            description: "Original dice",
            tags: ["combat", "roll"],
            category: .rules,
            displayState: 2,
            dice: [
                DieModel(id: UUID(), die: .twenty),
                DieModel(id: UUID(), die: .six)
            ],
            sumUp: false,
            modifier: 3,
            percentDice: true,
            compareOption: .higher,
            compareValue: 10,
            coupValues: [.diceValue(20)],
            coupOnlyOnFirstDie: true,
            fumbleValues: [.result(1)],
            fumbleOnlyOnFirstDie: false,
            reroleOptions: [DiceModel.RerollOption(number: 1, value: 1, maxDiceValue: true)],
            reorderDice: true,
            addDiceEvery: 5,
            entries: [firstEntry, secondEntry],
            parentId: parentId
        )

        try sut.replaceSync(id: itemId, with: original)
        try await sut.save()

        let fetchedOriginal = try #require(try await sut.fetch(id: itemId) as? DiceModel)
        #expect(fetchedOriginal.name == "Attack")
        #expect(fetchedOriginal.description == "Original dice")
        #expect(fetchedOriginal.tags == ["combat", "roll"])
        #expect(fetchedOriginal.category == .rules)
        #expect(fetchedOriginal.displayState == 2)
        #expect(fetchedOriginal.dice.map(\.die.text) == ["d20", "d6"])
        #expect(fetchedOriginal.sumUp == false)
        #expect(fetchedOriginal.modifier == 3)
        #expect(fetchedOriginal.percentDice == true)
        #expect(fetchedOriginal.compareOption == .higher)
        #expect(fetchedOriginal.compareValue == 10)
        #expect(fetchedOriginal.coupValues == [.diceValue(20)])
        #expect(fetchedOriginal.coupOnlyOnFirstDie == true)
        #expect(fetchedOriginal.fumbleValues == [.result(1)])
        #expect(fetchedOriginal.fumbleOnlyOnFirstDie == false)
        #expect(fetchedOriginal.rerollOptions == [DiceModel.RerollOption(number: 1, value: 1, maxDiceValue: true)])
        #expect(fetchedOriginal.reorderDice == true)
        #expect(fetchedOriginal.addDiceEvery == 5)
        #expect(fetchedOriginal.parentId == parentId)
        #expect(fetchedOriginal.entries.map(\.id) == [firstEntry.id, secondEntry.id])
        #expect(fetchedOriginal.entries.map(\.childId) == [firstEntry.childId, secondEntry.childId])

        let updatedEntry = ChildEntryModel(id: secondEntry.id, childId: UUID())
        let updated = DiceModel(
            id: itemId,
            name: "Attack Revised",
            description: "Updated dice",
            tags: ["combat"],
            category: .rules,
            displayState: 4,
            dice: [DieModel(id: UUID(), die: .ten)],
            sumUp: true,
            modifier: 0,
            percentDice: false,
            compareOption: .off,
            compareValue: 0,
            coupValues: [],
            coupOnlyOnFirstDie: false,
            fumbleValues: [],
            fumbleOnlyOnFirstDie: false,
            reroleOptions: [],
            reorderDice: false,
            addDiceEvery: 0,
            entries: [updatedEntry],
            parentId: nil
        )

        try await sut.replace(id: itemId, with: updated)
        try await sut.save()

        let fetchedUpdated = try #require(try await sut.fetch(id: itemId) as? DiceModel)
        #expect(fetchedUpdated.name == "Attack Revised")
        #expect(fetchedUpdated.description == "Updated dice")
        #expect(fetchedUpdated.tags == ["combat"])
        #expect(fetchedUpdated.displayState == 4)
        #expect(fetchedUpdated.dice.map(\.die.text) == ["d10"])
        #expect(fetchedUpdated.sumUp == true)
        #expect(fetchedUpdated.modifier == 0)
        #expect(fetchedUpdated.percentDice == false)
        #expect(fetchedUpdated.compareOption == .off)
        #expect(fetchedUpdated.coupValues == [])
        #expect(fetchedUpdated.fumbleValues == [])
        #expect(fetchedUpdated.rerollOptions == [])
        #expect(fetchedUpdated.reorderDice == false)
        #expect(fetchedUpdated.addDiceEvery == 0)
        #expect(fetchedUpdated.parentId == nil)
        #expect(fetchedUpdated.entries.map(\.id) == [updatedEntry.id])
        #expect(fetchedUpdated.entries.first?.childId == updatedEntry.childId)

        #expect(Set(try await sut.fetchIds()) == Set([itemId]))
        #expect(try await sut.fetchAll().count == 1)

        try await sut.delete(id: itemId)
        try await sut.save()

        let deleted = try await sut.fetch(id: itemId)
        #expect(deleted == nil)
        #expect(try await sut.fetchIds().isEmpty)
    }
}

private struct PersistentTestStore {
    let container: NSPersistentContainer
    let context: NSManagedObjectContext
    let batchContext: NSManagedObjectContext

    @MainActor
    init(bundles: [Bundle]) throws {
        let model = try #require(NSManagedObjectModel.mergedModel(from: bundles))
        container = NSPersistentContainer(name: "DataControllerTests-\(UUID().uuidString)", managedObjectModel: model)

        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        description.shouldAddStoreAsynchronously = false
        container.persistentStoreDescriptions = [description]

        var loadError: (any Error)?
        container.loadPersistentStores { _, error in
            loadError = error
        }
        if let loadError {
            throw loadError
        }

        context = container.newBackgroundContext()
        batchContext = container.newBackgroundContext()
    }
}
#endif
