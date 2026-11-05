// @copyright André Trettin

#if canImport(Testing)
import CoreData
import CoreRPG
import Foundation
import Testing

@testable import AdventureRPG

@MainActor
struct DataControllerTests {
    @Test func replaceFetchUpdateAndDelete() async throws {
        let store = try PersistentTestStore(bundles: [
            CoreRPG.Resources.bundle,
            AdventureRPG.Resources.bundle
        ])
        let sut = DataController(context: store.context, token: NetworkModules.adventure.token)

        let itemId = UUID()
        let parentId = UUID()
        let photoId = UUID()
        let diceId = UUID()
        let firstEntry = AdventureEntryModel(id: UUID(), name: "Arrival", content: "Open the gate")
        let secondEntry = AdventureEntryModel(id: UUID(), name: "Twist", content: "The key is gone")
        let original = AdventureModel(
            id: itemId,
            name: "Journey",
            description: "Original adventure",
            tags: ["campaign", "gate"],
            category: .campaign,
            displayState: 2,
            photoId: photoId,
            diceId: diceId,
            entries: [firstEntry, secondEntry],
            parentId: parentId
        )

        try sut.replaceSync(id: itemId, with: original)
        try await sut.save()

        let fetchedOriginal = try #require(try await sut.fetch(id: itemId) as? AdventureModel)
        #expect(fetchedOriginal.name == "Journey")
        #expect(fetchedOriginal.description == "Original adventure")
        #expect(fetchedOriginal.tags == ["campaign", "gate"])
        #expect(fetchedOriginal.category == .campaign)
        #expect(fetchedOriginal.displayState == 2)
        #expect(fetchedOriginal.photoId == photoId)
        #expect(fetchedOriginal.diceId == diceId)
        #expect(fetchedOriginal.parentId == parentId)
        #expect(fetchedOriginal.entries.map(\.id) == [firstEntry.id, secondEntry.id])
        #expect(fetchedOriginal.entries.map(\.name) == ["Arrival", "Twist"])
        #expect(fetchedOriginal.entries.map(\.content) == ["Open the gate", "The key is gone"])

        let updatedEntry = AdventureEntryModel(id: secondEntry.id, name: "Twist Revised", content: "The key was hidden")
        let updated = AdventureModel(
            id: itemId,
            name: "Journey Revised",
            description: "Updated adventure",
            tags: ["campaign"],
            category: .scenario,
            displayState: 4,
            photoId: nil,
            diceId: nil,
            entries: [updatedEntry],
            parentId: nil
        )

        try await sut.replace(id: itemId, with: updated)
        try await sut.save()

        let fetchedUpdated = try #require(try await sut.fetch(id: itemId) as? AdventureModel)
        #expect(fetchedUpdated.name == "Journey Revised")
        #expect(fetchedUpdated.description == "Updated adventure")
        #expect(fetchedUpdated.tags == ["campaign"])
        #expect(fetchedUpdated.category == .scenario)
        #expect(fetchedUpdated.displayState == 4)
        #expect(fetchedUpdated.photoId == nil)
        #expect(fetchedUpdated.diceId == nil)
        #expect(fetchedUpdated.parentId == nil)
        #expect(fetchedUpdated.entries.map(\.id) == [updatedEntry.id])
        #expect(fetchedUpdated.entries.first?.name == "Twist Revised")
        #expect(fetchedUpdated.entries.first?.content == "The key was hidden")

        #expect(Set(try await sut.fetchIds()) == Set([itemId]))
        #expect(try await sut.fetchAll().count == 1)

        try await sut.delete(id: itemId)
        try await sut.save()

        let deleted = try await sut.fetch(id: itemId)
        #expect(deleted == nil)
        #expect(try await sut.fetchIds().isEmpty)
    }

    @Test func adventureDataControllerCreatesTrimmedEntry() async throws {
        let store = try PersistentTestStore(bundles: [
            CoreRPG.Resources.bundle,
            AdventureRPG.Resources.bundle
        ])
        let photoId = UUID()
        let sut = AdventureDataController()

        await sut.addNewAdventure(
            context: store.context,
            name: "  Quest  ",
            text: "  Find the door  ",
            photoIds: [photoId],
            photoLinks: ["photo://one", "photo://two"]
        )

        let dataController = DataController(context: store.context, token: NetworkModules.adventure.token)
        let models = try await dataController.fetch()
        let model = try #require(models.first)

        #expect(model.name == "Quest")
        #expect(model.description == "Find the door")
        #expect(model.category == .entry)
        #expect(model.photoId == photoId)
        #expect(model.entries.count == 1)
        #expect(model.entries.first?.content == "photo://one, photo://two")
    }

    @Test func tablePlayersPersistThroughCoreData() async throws {
        let store = try PersistentTestStore(bundles: [
            CoreRPG.Resources.bundle,
            AdventureRPG.Resources.bundle
        ])
        let sut = DataController(context: store.context, token: NetworkModules.adventure.token)
        let tablePlayers = [TablePlayerModel(characterId: UUID()), TablePlayerModel(characterId: UUID(), isEnabled: false)]
        let without = AdventureModel(id: UUID(), name: "Journey")
        let with = AdventureModel(id: UUID(), name: "Journey", tablePlayers: tablePlayers)

        try sut.replaceSync(id: without.id, with: without)
        try sut.replaceSync(id: with.id, with: with)
        try await sut.save()

        let fetchedWithout = try #require(try await sut.fetch(id: without.id) as? AdventureModel)
        #expect(fetchedWithout.tablePlayers.isEmpty)
        let fetchedWith = try #require(try await sut.fetch(id: with.id) as? AdventureModel)
        #expect(fetchedWith.tablePlayers == tablePlayers)

        let emptied = fetchedWith.copy()
        emptied.tablePlayers = []
        try await sut.replace(id: with.id, with: emptied)
        try await sut.save()

        let fetchedEmptied = try #require(try await sut.fetch(id: with.id) as? AdventureModel)
        #expect(fetchedEmptied.tablePlayers.isEmpty)
        // The emptied list keeps its clock, so it wins over the copy it replaced.
        #expect(fetchedWith.merge(fetchedEmptied).tablePlayers.isEmpty)
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
