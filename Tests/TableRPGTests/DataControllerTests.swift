// @copyright André Trettin

#if canImport(Testing)
import CoreData
import CoreRPG
import Foundation
import Testing

@testable import TableRPG

@MainActor
struct DataControllerTests {
    @Test func replaceFetchUpdateAndDelete() async throws {
        let store = try PersistentTestStore(bundles: [
            CoreRPG.Resources.bundle,
            TableRPG.Resources.bundle
        ])
        let sut = DataController(context: store.context, token: NetworkModules.table.token)

        let itemId = UUID()
        let parentId = UUID()
        let diceId = UUID()
        let firstEntry = TableEntryModel(id: UUID(), name: "One", content: "First result")
        let secondEntry = TableEntryModel(id: UUID(), name: "Two", content: "Second result")
        let original = TableModel(
            id: itemId,
            name: "Loot",
            description: "Original table",
            tags: ["loot", "forest"],
            category: .loot,
            displayState: 2,
            tableType: .dice,
            diceId: diceId,
            entries: [firstEntry, secondEntry],
            parentId: parentId
        )

        try sut.replaceSync(id: itemId, with: original)
        try await sut.save()

        let fetchedOriginal = try #require(try await sut.fetch(id: itemId) as? TableModel)
        #expect(fetchedOriginal.name == "Loot")
        #expect(fetchedOriginal.description == "Original table")
        #expect(fetchedOriginal.tags == ["loot", "forest"])
        #expect(fetchedOriginal.category == .loot)
        #expect(fetchedOriginal.displayState == 2)
        #expect(fetchedOriginal.tableType == .dice)
        #expect(fetchedOriginal.diceId == diceId)
        #expect(fetchedOriginal.parentId == parentId)
        #expect(fetchedOriginal.entries.map(\.id) == [firstEntry.id, secondEntry.id])
        #expect(fetchedOriginal.entries.map(\.name) == ["One", "Two"])
        #expect(fetchedOriginal.entries.map(\.content) == ["First result", "Second result"])

        let updatedEntry = TableEntryModel(id: secondEntry.id, name: "Two Revised", content: "Updated result")
        let updated = TableModel(
            id: itemId,
            name: "Loot Revised",
            description: "Updated table",
            tags: ["loot"],
            category: .generator,
            displayState: 4,
            tableType: .all,
            diceId: nil,
            entries: [updatedEntry],
            parentId: nil
        )

        try await sut.replace(id: itemId, with: updated)
        try await sut.save()

        let fetchedUpdated = try #require(try await sut.fetch(id: itemId) as? TableModel)
        #expect(fetchedUpdated.name == "Loot Revised")
        #expect(fetchedUpdated.description == "Updated table")
        #expect(fetchedUpdated.tags == ["loot"])
        #expect(fetchedUpdated.category == .generator)
        #expect(fetchedUpdated.displayState == 4)
        #expect(fetchedUpdated.tableType == .all)
        #expect(fetchedUpdated.diceId == nil)
        #expect(fetchedUpdated.parentId == nil)
        #expect(fetchedUpdated.entries.map(\.id) == [updatedEntry.id])
        #expect(fetchedUpdated.entries.first?.name == "Two Revised")
        #expect(fetchedUpdated.entries.first?.content == "Updated result")

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
    }
}
#endif
