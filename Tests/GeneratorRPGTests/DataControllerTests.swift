// @copyright André Trettin

#if canImport(Testing)
import CoreData
import CoreRPG
import Foundation
import Testing

@testable import GeneratorRPG

@MainActor
struct DataControllerTests {
    @Test func replaceFetchUpdateAndDelete() async throws {
        let store = try PersistentTestStore(bundles: [
            CoreRPG.Resources.bundle,
            GeneratorRPG.Resources.bundle
        ])
        let sut = DataController(context: store.context, batchContext: store.batchContext, token: NetworkModules.generator.token)

        let itemId = UUID()
        let parentId = UUID()
        let referenceId = UUID()
        let firstEntry = ChildEntryModel(id: UUID(), childId: UUID())
        let secondEntry = ChildEntryModel(id: UUID(), childId: UUID())
        let original = GeneratorModel(
            id: itemId,
            name: "Adventure Prompt",
            description: "Original generator",
            tags: ["prompt", "story"],
            category: .item,
            displayState: 2,
            entries: [firstEntry, secondEntry],
            parentId: parentId,
            genType: .adventure,
            referenceId: referenceId
        )

        try sut.replaceSync(id: itemId, with: original)
        try await sut.save()

        let fetchedOriginal = try #require(try await sut.fetch(id: itemId) as? GeneratorModel)
        #expect(fetchedOriginal.name == "Adventure Prompt")
        #expect(fetchedOriginal.description == "Original generator")
        #expect(fetchedOriginal.tags == ["prompt", "story"])
        #expect(fetchedOriginal.category == .item)
        #expect(fetchedOriginal.displayState == 2)
        #expect(fetchedOriginal.parentId == parentId)
        #expect(fetchedOriginal.genType == .adventure)
        #expect(fetchedOriginal.referenceId == referenceId)
        #expect(fetchedOriginal.entries.map(\.id) == [firstEntry.id, secondEntry.id])
        #expect(fetchedOriginal.entries.map(\.childId) == [firstEntry.childId, secondEntry.childId])

        let updatedEntry = ChildEntryModel(id: secondEntry.id, childId: UUID())
        let updated = GeneratorModel(
            id: itemId,
            name: "Character Prompt",
            description: "Updated generator",
            tags: ["prompt"],
            category: .item,
            displayState: 4,
            entries: [updatedEntry],
            parentId: nil,
            genType: .character,
            referenceId: nil
        )

        try await sut.replace(id: itemId, with: updated)
        try await sut.save()

        let fetchedUpdated = try #require(try await sut.fetch(id: itemId) as? GeneratorModel)
        #expect(fetchedUpdated.name == "Character Prompt")
        #expect(fetchedUpdated.description == "Updated generator")
        #expect(fetchedUpdated.tags == ["prompt"])
        #expect(fetchedUpdated.displayState == 4)
        #expect(fetchedUpdated.parentId == nil)
        #expect(fetchedUpdated.genType == .character)
        #expect(fetchedUpdated.referenceId == nil)
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
