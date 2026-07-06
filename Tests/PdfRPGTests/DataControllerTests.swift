// @copyright André Trettin

#if canImport(Testing)
import CoreData
import CoreGraphics
import CoreRPG
import Foundation
import Testing

@testable import PdfRPG

@MainActor
struct DataControllerTests {
    @Test func replaceFetchUpdateAndDelete() async throws {
        let store = try PersistentTestStore(bundles: [
            CoreRPG.Resources.bundle,
            PdfRPG.Resources.bundle
        ])
        let sut = DataController(context: store.context, batchContext: store.batchContext, token: NetworkModules.pdf.token)

        let itemId = UUID()
        let parentId = UUID()
        let firstEntry = PdfEntryModel(
            id: UUID(),
            name: "Chapter One",
            content: "Opening notes",
            pageNumber: "1",
            bounds: CGRect(x: 10, y: 20, width: 30, height: 40)
        )
        let secondEntry = PdfEntryModel(
            id: UUID(),
            name: "Chapter Two",
            content: "Deep rules",
            pageNumber: "8",
            bounds: CGRect(x: 11, y: 22, width: 33, height: 44)
        )
        let fileUrl = FileUrl(
            fileId: itemId,
            url: URL(filePath: "/tmp/rules.pdf"),
            location: .local,
            module: NetworkModules.pdf.token,
            relativeUrl: nil,
            contentHash: "rules-hash"
        )
        let original = PdfModel(
            id: itemId,
            name: "Rules",
            description: "Original book",
            tags: ["rules", "combat"],
            category: .rules,
            displayState: 3,
            fileUrl: fileUrl,
            entries: [firstEntry, secondEntry],
            parentId: parentId
        )

        try sut.replaceSync(id: itemId, with: original)
        try await sut.save()

        let fetchedOriginal = try #require(try await sut.fetch(id: itemId) as? PdfModel)
        #expect(fetchedOriginal.name == "Rules")
        #expect(fetchedOriginal.description == "Original book")
        #expect(fetchedOriginal.tags == ["rules", "combat"])
        #expect(fetchedOriginal.category == .rules)
        #expect(fetchedOriginal.displayState == 3)
        #expect(fetchedOriginal.fileUrl == fileUrl)
        #expect(fetchedOriginal.parentId == parentId)
        #expect(fetchedOriginal.entries.map(\.id) == [firstEntry.id, secondEntry.id])
        #expect(fetchedOriginal.entries.first?.bounds == firstEntry.bounds)

        let updatedEntry = PdfEntryModel(
            id: secondEntry.id,
            name: "Chapter Two Revised",
            content: "Tighter rules",
            pageNumber: "9",
            bounds: CGRect(x: 1, y: 2, width: 3, height: 4)
        )
        let updated = PdfModel(
            id: itemId,
            name: "Rules Revised",
            description: "Updated book",
            tags: ["rules"],
            category: .rules,
            displayState: 5,
            fileUrl: nil,
            entries: [updatedEntry],
            parentId: nil
        )

        try await sut.replace(id: itemId, with: updated)
        try await sut.save()

        let fetchedUpdated = try #require(try await sut.fetch(id: itemId) as? PdfModel)
        #expect(fetchedUpdated.name == "Rules Revised")
        #expect(fetchedUpdated.description == "Updated book")
        #expect(fetchedUpdated.tags == ["rules"])
        #expect(fetchedUpdated.displayState == 5)
        #expect(fetchedUpdated.fileUrl == nil)
        #expect(fetchedUpdated.parentId == nil)
        #expect(fetchedUpdated.entries.map(\.id) == [updatedEntry.id])
        #expect(fetchedUpdated.entries.first?.name == "Chapter Two Revised")
        #expect(fetchedUpdated.entries.first?.content == "Tighter rules")
        #expect(fetchedUpdated.entries.first?.pageLabel == "9")
        #expect(fetchedUpdated.entries.first?.bounds == updatedEntry.bounds)

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
