// @copyright André Trettin

#if canImport(Testing)
import CoreData
import CoreRPG
import Foundation
import Testing

@testable import CharacterRPG

@MainActor
struct DataControllerTests {
    @Test func replaceFetchUpdateAndDelete() async throws {
        let store = try PersistentTestStore(bundles: [
            CoreRPG.Resources.bundle,
            CharacterRPG.Resources.bundle
        ])
        let sut = DataController(context: store.context, token: NetworkModules.value.token)

        let itemId = UUID()
        let parentId = UUID()
        let diceId = UUID()
        let groupId = UUID()
        let photoId = UUID()
        let firstGalleryPhotoId = UUID()
        let secondGalleryPhotoId = UUID()
        let linkedValueId = UUID()
        let firstEntry = ValueEntryModel(
            id: UUID(),
            name: "Strength",
            type: .number,
            isGenerator: true,
            value: "10",
            diceId: diceId,
            valueId: linkedValueId
        )
        let secondEntry = ValueEntryModel(
            id: UUID(),
            name: "Notes",
            type: .text,
            value: "Brave and loud"
        )
        let original = ValueModel(
            id: itemId,
            name: "Knight",
            description: "Original character",
            tags: ["npc", "frontline"],
            category: .character,
            displayState: 2,
            photoId: photoId,
            photos: [firstGalleryPhotoId, secondGalleryPhotoId],
            entries: [firstEntry, secondEntry],
            parentId: parentId,
            diceId: diceId,
            groupId: groupId
        )

        try sut.replaceSync(id: itemId, with: original)
        try await sut.save()

        let fetchedOriginal = try #require(try await sut.fetch(id: itemId) as? ValueModel)
        #expect(fetchedOriginal.name == "Knight")
        #expect(fetchedOriginal.description == "Original character")
        #expect(fetchedOriginal.tags == ["npc", "frontline"])
        #expect(fetchedOriginal.category == .character)
        #expect(fetchedOriginal.displayState == 2)
        #expect(fetchedOriginal.photoId == photoId)
        #expect(fetchedOriginal.photos == [firstGalleryPhotoId, secondGalleryPhotoId])
        #expect(fetchedOriginal.parentId == parentId)
        #expect(fetchedOriginal.diceId == diceId)
        #expect(fetchedOriginal.groupId == groupId)
        #expect(fetchedOriginal.entries.map(\.id) == [firstEntry.id, secondEntry.id])
        #expect(fetchedOriginal.entries.first?.name == "Strength")
        #expect(fetchedOriginal.entries.first?.type == .number)
        #expect(fetchedOriginal.entries.first?.isGenerator == true)
        #expect(fetchedOriginal.entries.first?.value == "10")
        #expect(fetchedOriginal.entries.first?.diceId == diceId)
        #expect(fetchedOriginal.entries.first?.valueId == linkedValueId)

        let updatedEntry = ValueEntryModel(
            id: secondEntry.id,
            name: "Notes Revised",
            type: .selection,
            isGenerator: false,
            value: "I"
        )
        let updated = ValueModel(
            id: itemId,
            name: "Knight Revised",
            description: "Updated character",
            tags: ["npc"],
            category: .monster,
            displayState: 4,
            photoId: nil,
            photos: [secondGalleryPhotoId],
            entries: [updatedEntry],
            parentId: nil,
            diceId: nil,
            groupId: nil
        )

        try await sut.replace(id: itemId, with: updated)
        try await sut.save()

        let fetchedUpdated = try #require(try await sut.fetch(id: itemId) as? ValueModel)
        #expect(fetchedUpdated.name == "Knight Revised")
        #expect(fetchedUpdated.description == "Updated character")
        #expect(fetchedUpdated.tags == ["npc"])
        #expect(fetchedUpdated.category == .monster)
        #expect(fetchedUpdated.displayState == 4)
        #expect(fetchedUpdated.photoId == nil)
        #expect(fetchedUpdated.photos == [secondGalleryPhotoId])
        #expect(fetchedUpdated.parentId == nil)
        #expect(fetchedUpdated.diceId == nil)
        #expect(fetchedUpdated.groupId == nil)
        #expect(fetchedUpdated.entries.map(\.id) == [updatedEntry.id])
        #expect(fetchedUpdated.entries.first?.name == "Notes Revised")
        #expect(fetchedUpdated.entries.first?.type == .selection)
        #expect(fetchedUpdated.entries.first?.value == "I")

        #expect(Set(try await sut.fetchIds()) == Set([itemId]))
        #expect(try await sut.fetchAll().count == 1)

        try await sut.delete(id: itemId)
        try await sut.save()

        let deleted = try await sut.fetch(id: itemId)
        #expect(deleted == nil)
        #expect(try await sut.fetchIds().isEmpty)
    }

    @Test func characterDataControllerCreatesTrimmedValue() async throws {
        let store = try PersistentTestStore(bundles: [
            CoreRPG.Resources.bundle,
            CharacterRPG.Resources.bundle
        ])
        let photoIds = [UUID(), UUID()]
        let sut = CharacterDataController()

        await sut.addNewValue(
            context: store.context,
            name: "  Captain  ",
            text: "  Keeps the watch  ",
            photoIds: photoIds
        )

        let dataController = DataController(context: store.context, token: NetworkModules.value.token)
        let models = try await dataController.fetch()
        let model = try #require(models.first)

        #expect(model.name == "Captain")
        #expect(model.description == "Keeps the watch")
        #expect(model.category == .entry)
        #expect(model.photos == photoIds)
        #expect(model.photoId == photoIds.first)
    }

    @Test func characterDataControllerWithoutPhotosHasNoPortrait() async throws {
        let store = try PersistentTestStore(bundles: [
            CoreRPG.Resources.bundle,
            CharacterRPG.Resources.bundle
        ])

        await CharacterDataController().addNewValue(context: store.context, name: "Scribe", text: "", photoIds: [])

        let dataController = DataController(context: store.context, token: NetworkModules.value.token)
        let model = try #require(try await dataController.fetch().first)
        #expect(model.photoId == nil)
        #expect(model.photos.isEmpty)
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
