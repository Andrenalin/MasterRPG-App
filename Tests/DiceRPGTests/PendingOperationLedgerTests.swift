// @copyright André Trettin

#if canImport(Testing)
import CoreData
import CoreRPG
import Foundation
import Testing

@testable import DiceRPG

/// CODE_AUDIT_18 §5.2 / §5.3: unsaved inserts are protected from the sync-deletion diff, and a
/// rollback of the shared context re-queues flushed-but-unsaved edits instead of losing them.
@MainActor
struct PendingOperationLedgerTests {
    private func makeStore() throws -> LedgerTestStore {
        try LedgerTestStore(bundles: [
            CoreRPG.Resources.bundle,
            DiceRPG.Resources.bundle
        ])
    }

    private func dice(_ id: UUID, name: String) -> DiceModel {
        DiceModel(id: id, name: name, description: "", tags: [], category: .rules, displayState: 0, dice: [DieModel(id: UUID(), die: .six)])
    }

    @Test func unsavedInsertStaysProtectedUntilCommitted() async throws {
        let store = try makeStore()
        let sut = DataController(context: store.context, token: NetworkModules.dice.token)
        let itemId = UUID()

        try sut.replaceSync(id: itemId, with: dice(itemId, name: "New"))
        sut.markUnsavedInsert(id: itemId)
        #expect(await sut.unsavedInsertIds() == [itemId])
        #expect(try await sut.fetchIds().isEmpty)

        try await sut.save()

        #expect(await sut.unsavedInsertIds().isEmpty)
        #expect(try await sut.fetchIds() == [itemId])
    }

    @Test func deletingAnUnsavedInsertClearsItsProtection() async throws {
        let store = try makeStore()
        let sut = DataController(context: store.context, token: NetworkModules.dice.token)
        let itemId = UUID()

        try sut.replaceSync(id: itemId, with: dice(itemId, name: "New"))
        sut.markUnsavedInsert(id: itemId)
        await sut.removePendingOperations(for: itemId)

        #expect(await sut.unsavedInsertIds().isEmpty)
        try await sut.save()
        #expect(try await sut.fetchIds().isEmpty)
    }

    @Test func rollbackOfTheSharedContextRequeuesFlushedEdits() async throws {
        let store = try makeStore()
        let first = DataController(context: store.context, token: NetworkModules.dice.token)
        let second = DataController(context: store.context, token: NetworkModules.dice.token)
        let firstId = UUID()
        let secondId = UUID()

        try first.replaceSync(id: firstId, with: dice(firstId, name: "First"))
        first.markUnsavedInsert(id: firstId)
        try second.replaceSync(id: secondId, with: dice(secondId, name: "Second"))
        try await first.flushPendingOperations()
        try await second.flushPendingOperations()

        // Some other module's failed save rolls the shared context back.
        await store.context.perform {
            store.context.rollbackRestoringFlushedOperations()
        }
        #expect(try await first.fetchIds().isEmpty)
        #expect(await first.unsavedInsertIds() == [firstId])

        // The next save re-applies both modules' edits instead of losing them.
        try await first.save()
        try await second.save()
        #expect(Set(try await first.fetchIds()) == [firstId, secondId])
        #expect(await first.unsavedInsertIds().isEmpty)
    }
}

private struct LedgerTestStore {
    let container: NSPersistentContainer
    let context: NSManagedObjectContext

    @MainActor
    init(bundles: [Bundle]) throws {
        let model = try #require(NSManagedObjectModel.mergedModel(from: bundles))
        container = NSPersistentContainer(name: "PendingOperationLedgerTests-\(UUID().uuidString)", managedObjectModel: model)

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
