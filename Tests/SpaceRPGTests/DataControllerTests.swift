// @copyright André Trettin

#if canImport(Testing)
import CoreData
import CoreRPG
import Foundation
import Testing

@testable import SpaceRPG

@MainActor
struct DataControllerTests {
    @Test func replaceFetchUpdateAndDelete() async throws {
        let store = try PersistentTestStore(bundles: [
            CoreRPG.Resources.bundle,
            SpaceRPG.Resources.bundle
        ])
        let sut = DataController(context: store.context, batchContext: store.batchContext, token: NetworkModules.space.token)

        let itemId = UUID()
        let parentId = UUID()
        let firstEntry = SpaceEntryModel(id: UUID(), spaceId: UUID())
        let secondEntry = SpaceEntryModel(id: UUID(), spaceId: UUID())
        let fileUrl = FileUrl(
            fileId: itemId,
            url: URL(filePath: "/tmp/model.usdz"),
            location: .appCloud,
            module: NetworkModules.space.token,
            relativeUrl: nil,
            contentHash: "space-hash"
        )
        let original = SpaceModel(
            id: itemId,
            name: "Temple",
            description: "Original space",
            tags: ["map", "ancient"],
            category: .item,
            displayState: 2,
            degrees: 90,
            fileUrl: fileUrl,
            entries: [firstEntry, secondEntry],
            parentId: parentId
        )

        try sut.replaceSync(id: itemId, with: original)
        try await sut.save()

        let fetchedOriginal = try #require(try await sut.fetch(id: itemId) as? SpaceModel)
        #expect(fetchedOriginal.name == "Temple")
        #expect(fetchedOriginal.description == "Original space")
        #expect(fetchedOriginal.tags == ["map", "ancient"])
        #expect(fetchedOriginal.category == .item)
        #expect(fetchedOriginal.displayState == 2)
        #expect(fetchedOriginal.degrees == 90)
        #expect(fetchedOriginal.fileUrl == fileUrl)
        #expect(fetchedOriginal.parentId == parentId)
        #expect(fetchedOriginal.entries.map(\.id) == [firstEntry.id, secondEntry.id])
        #expect(fetchedOriginal.entries.map(\.spaceId) == [firstEntry.spaceId, secondEntry.spaceId])

        let updatedEntry = SpaceEntryModel(id: secondEntry.id, spaceId: UUID())
        let updated = SpaceModel(
            id: itemId,
            name: "Temple Revised",
            description: "Updated space",
            tags: ["ancient"],
            category: .item,
            displayState: 4,
            degrees: 180,
            fileUrl: nil,
            entries: [updatedEntry],
            parentId: nil
        )

        try await sut.replace(id: itemId, with: updated)
        try await sut.save()

        let fetchedUpdated = try #require(try await sut.fetch(id: itemId) as? SpaceModel)
        #expect(fetchedUpdated.name == "Temple Revised")
        #expect(fetchedUpdated.description == "Updated space")
        #expect(fetchedUpdated.tags == ["ancient"])
        #expect(fetchedUpdated.displayState == 4)
        #expect(fetchedUpdated.degrees == 180)
        #expect(fetchedUpdated.fileUrl == nil)
        #expect(fetchedUpdated.parentId == nil)
        #expect(fetchedUpdated.entries.map(\.id) == [updatedEntry.id])
        #expect(fetchedUpdated.entries.first?.spaceId == updatedEntry.spaceId)

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
