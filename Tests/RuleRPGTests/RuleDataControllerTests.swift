// @copyright André Trettin

#if canImport(Testing)
import CoreData
import CoreRPG
import Foundation
import Testing

@testable import RuleRPG

@Suite("Rule Core Data", .serialized)
@MainActor
struct RuleDataControllerTests {
    @Test("Core Data round trips source payloads, ordered sections, updates, and deletion")
    func persistenceRoundTrip() async throws {
        // Given
        let store = try RulePersistentTestStore(bundles: [
            CoreRPG.Resources.bundle,
            RuleRPG.Resources.bundle
        ])
        let controller = DataController(
            context: store.context,
            batchContext: store.batchContext,
            token: NetworkModules.rule.token
        )
        let itemID = try #require(UUID(uuidString: "730A837D-BB12-4200-B65D-AF0C34F1E0DF"))
        let parentID = try #require(UUID(uuidString: "A2E6EA55-F3D2-4731-BA3A-A3C6D5278183"))
        let firstID = try #require(UUID(uuidString: "287051B2-6EC2-4C43-A0D4-A94512B51D76"))
        let secondID = try #require(UUID(uuidString: "9FCBBD66-61F2-47AB-B734-059A8D4D1EC6"))
        let payload: FoundryJSONValue = .object([
            "_id": .string("source-rule"),
            "system": .object(["rank": .integer(3)])
        ])
        let metadata = RuleSourceMetadata(
            sourceIdentifier: "source-rule",
            systemID: "ds4",
            systemTitle: "Dungeon Slayers 4",
            systemVersion: "4.2",
            packageIdentifier: "ds4.rules",
            packageName: "Rules",
            documentID: "source-rule",
            documentType: "Item",
            subtype: "talent",
            ruleCategory: "talent",
            imagePath: "icons/rule.webp"
        )
        let original = RuleModel.fixture(
            id: itemID,
            name: "Persisted Rule",
            description: "Original description",
            tags: ["one", "two"],
            displayState: 4,
            entries: [
                .fixture(id: firstID, name: "First", content: "A", kind: .text, displayState: 1),
                .fixture(id: secondID, name: "Second", content: "B", kind: .effect, displayState: 2)
            ],
            sourceMetadata: metadata,
            sourcePayload: .foundryDocument(payload),
            parentId: parentID
        )

        // When
        try controller.replaceSync(id: itemID, with: original)
        try await controller.save()
        let fetched = try #require(try await controller.fetch(id: itemID) as? RuleModel)

        // Then
        #expect(fetched.id == original.id)
        #expect(fetched.name == original.name)
        #expect(fetched.description == original.description)
        #expect(fetched.tags == original.tags)
        #expect(fetched.category == original.category)
        #expect(fetched.displayState == original.displayState)
        #expect(fetched.entries.map(\.id) == [firstID, secondID])
        #expect(fetched.entries.map(\.name) == ["First", "Second"])
        #expect(fetched.entries.map(\.content) == ["A", "B"])
        #expect(fetched.entries.map(\.kind) == [.text, .effect])
        #expect(fetched.entries.map(\.displayState) == [1, 2])
        #expect(fetched.sourceMetadata == metadata)
        #expect(fetched.sourcePayload == .foundryDocument(payload))
        #expect(fetched.parentId == parentID)
        #expect(try await controller.fetchIds() == [itemID])

        // When updating, the removed entry must not remain as a Core Data orphan.
        let updated = RuleModel.fixture(
            id: itemID,
            name: "Persisted Rule Revised",
            description: "Updated description",
            tags: ["two"],
            entries: [.fixture(id: secondID, name: "Second Revised", content: "B2", kind: .value)],
            sourceMetadata: metadata,
            sourcePayload: .foundryDocument(payload)
        )
        try await controller.replace(id: itemID, with: updated)
        try await controller.save()
        let fetchedUpdated = try #require(try await controller.fetch(id: itemID) as? RuleModel)
        let entryCount = try await store.context.perform {
            try store.context.count(for: NSFetchRequest<NSFetchRequestResult>(entityName: "RPGRuleEntry"))
        }

        // Then
        #expect(fetchedUpdated.id == updated.id)
        #expect(fetchedUpdated.name == updated.name)
        #expect(fetchedUpdated.description == updated.description)
        #expect(fetchedUpdated.tags == updated.tags)
        #expect(fetchedUpdated.category == updated.category)
        #expect(fetchedUpdated.displayState == updated.displayState)
        #expect(fetchedUpdated.entries.map(\.id) == [secondID])
        #expect(fetchedUpdated.entries.map(\.name) == ["Second Revised"])
        #expect(fetchedUpdated.entries.map(\.content) == ["B2"])
        #expect(fetchedUpdated.entries.map(\.kind) == [.value])
        #expect(fetchedUpdated.entries.map(\.displayState) == [0])
        #expect(fetchedUpdated.sourceMetadata == metadata)
        #expect(fetchedUpdated.sourcePayload == .foundryDocument(payload))
        #expect(fetchedUpdated.parentId == nil)
        #expect(entryCount == 1)

        // When / Then deleting
        try await controller.delete(id: itemID)
        try await controller.save()
        #expect(try await controller.fetch(id: itemID) == nil)
        #expect(try await controller.fetchIds().isEmpty)
    }
}

private struct RulePersistentTestStore {
    let container: NSPersistentContainer
    let context: NSManagedObjectContext
    let batchContext: NSManagedObjectContext

    @MainActor
    init(bundles: [Bundle]) throws {
        let model = try #require(NSManagedObjectModel.mergedModel(from: bundles))
        container = NSPersistentContainer(
            name: "RuleDataControllerTests",
            managedObjectModel: model
        )
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
