// @copyright André Trettin

#if canImport(Testing)
import CoreData
import CoreRPG
import Foundation
import Testing

@testable import AudioRPG

@MainActor
struct DataControllerTests {
    @Test func replaceFetchUpdateAndDelete() async throws {
        let store = try PersistentTestStore(bundles: [
            CoreRPG.Resources.bundle,
            AudioRPG.Resources.bundle
        ])
        let sut = DataController(context: store.context, batchContext: store.batchContext, token: NetworkModules.audio.token)

        let itemId = UUID()
        let parentId = UUID()
        let firstEntry = AudioEntryModel(id: UUID(), audioId: UUID())
        let secondEntry = AudioEntryModel(id: UUID(), audioId: UUID())
        let fileUrl = FileUrl(
            fileId: itemId,
            url: URL(filePath: "/tmp/theme.m4a"),
            location: .appCloud,
            module: NetworkModules.audio.token,
            relativeUrl: nil,
            contentHash: "audio-hash"
        )
        let original = AudioModel(
            id: itemId,
            name: "Theme",
            description: "Original audio",
            tags: ["music", "battle"],
            category: .music,
            displayState: 2,
            fileUrl: fileUrl,
            entries: [firstEntry, secondEntry],
            parentId: parentId
        )

        try sut.replaceSync(id: itemId, with: original)
        try await sut.save()

        let fetchedOriginal = try #require(try await sut.fetch(id: itemId) as? AudioModel)
        #expect(fetchedOriginal.name == "Theme")
        #expect(fetchedOriginal.description == "Original audio")
        #expect(fetchedOriginal.tags == ["music", "battle"])
        #expect(fetchedOriginal.category == .music)
        #expect(fetchedOriginal.displayState == 2)
        #expect(fetchedOriginal.fileUrl == fileUrl)
        #expect(fetchedOriginal.parentId == parentId)
        #expect(fetchedOriginal.entries.map(\.id) == [firstEntry.id, secondEntry.id])
        #expect(fetchedOriginal.entries.map(\.audioId) == [firstEntry.audioId, secondEntry.audioId])

        let updatedEntry = AudioEntryModel(id: secondEntry.id, audioId: UUID())
        let updated = AudioModel(
            id: itemId,
            name: "Theme Revised",
            description: "Updated audio",
            tags: ["music"],
            category: .sound,
            displayState: 4,
            fileUrl: nil,
            entries: [updatedEntry],
            parentId: nil
        )

        try await sut.replace(id: itemId, with: updated)
        try await sut.save()

        let fetchedUpdated = try #require(try await sut.fetch(id: itemId) as? AudioModel)
        #expect(fetchedUpdated.name == "Theme Revised")
        #expect(fetchedUpdated.description == "Updated audio")
        #expect(fetchedUpdated.tags == ["music"])
        #expect(fetchedUpdated.category == .sound)
        #expect(fetchedUpdated.displayState == 4)
        #expect(fetchedUpdated.fileUrl == nil)
        #expect(fetchedUpdated.parentId == nil)
        #expect(fetchedUpdated.entries.map(\.id) == [updatedEntry.id])
        #expect(fetchedUpdated.entries.first?.audioId == updatedEntry.audioId)

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
