// @copyright André Trettin

#if canImport(Testing)
import CoreData
import CoreRPG
import Foundation
import Testing

@testable import PhotoRPG

@MainActor
struct DataControllerTests {
    @Test func replaceFetchUpdateAndDelete() async throws {
        let store = try PersistentTestStore(bundles: [
            CoreRPG.Resources.bundle,
            PhotoRPG.Resources.bundle
        ])
        let sut = DataController(context: store.context, batchContext: store.batchContext, token: NetworkModules.photo.token)

        let itemId = UUID()
        let parentId = UUID()
        let firstEntry = PhotoEntryModel(id: UUID(), photoId: UUID())
        let secondEntry = PhotoEntryModel(id: UUID(), photoId: UUID())
        let fileUrl = FileUrl(
            fileId: itemId,
            url: URL(filePath: "/tmp/scene.png"),
            location: .local,
            module: NetworkModules.photo.token,
            relativeUrl: nil,
            contentHash: "photo-hash"
        )
        let original = PhotoModel(
            id: itemId,
            name: "Scene",
            description: "Original photo",
            tags: ["forest", "night"],
            category: .photo,
            displayState: 2,
            degrees: 45,
            fileUrl: fileUrl,
            entries: [firstEntry, secondEntry],
            parentId: parentId
        )

        try sut.replaceSync(id: itemId, with: original)
        try await sut.save()

        let fetchedOriginal = try #require(try await sut.fetch(id: itemId) as? PhotoModel)
        #expect(fetchedOriginal.name == "Scene")
        #expect(fetchedOriginal.description == "Original photo")
        #expect(fetchedOriginal.tags == ["forest", "night"])
        #expect(fetchedOriginal.category == .photo)
        #expect(fetchedOriginal.displayState == 2)
        #expect(fetchedOriginal.degrees == 45)
        #expect(fetchedOriginal.fileUrl == fileUrl)
        #expect(fetchedOriginal.parentId == parentId)
        #expect(fetchedOriginal.entries.map(\.id) == [firstEntry.id, secondEntry.id])
        #expect(fetchedOriginal.entries.map(\.photoId) == [firstEntry.photoId, secondEntry.photoId])

        let updatedEntry = PhotoEntryModel(id: secondEntry.id, photoId: UUID())
        let updated = PhotoModel(
            id: itemId,
            name: "Scene Revised",
            description: "Updated photo",
            tags: ["forest"],
            category: .photo,
            displayState: 4,
            degrees: 90,
            fileUrl: nil,
            entries: [updatedEntry],
            parentId: nil
        )

        try await sut.replace(id: itemId, with: updated)
        try await sut.save()

        let fetchedUpdated = try #require(try await sut.fetch(id: itemId) as? PhotoModel)
        #expect(fetchedUpdated.name == "Scene Revised")
        #expect(fetchedUpdated.description == "Updated photo")
        #expect(fetchedUpdated.tags == ["forest"])
        #expect(fetchedUpdated.displayState == 4)
        #expect(fetchedUpdated.degrees == 90)
        #expect(fetchedUpdated.fileUrl == nil)
        #expect(fetchedUpdated.parentId == nil)
        #expect(fetchedUpdated.entries.map(\.id) == [updatedEntry.id])
        #expect(fetchedUpdated.entries.first?.photoId == updatedEntry.photoId)

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
