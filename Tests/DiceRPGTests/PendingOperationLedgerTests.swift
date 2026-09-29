// @copyright André Trettin

#if canImport(Testing)
import CoreData
@testable import CoreRPG
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

    // MARK: - CODE_AUDIT_19

    /// §5.4: a delete used to go straight into the context, so another module's failed save
    /// rolled it back and the item came back on disk while it stayed gone in memory.
    @Test func deleteSurvivesARollbackOfTheSharedContext() async throws {
        let store = try makeStore()
        let sut = DataController(context: store.context, token: NetworkModules.dice.token)
        let itemId = UUID()
        try sut.replaceSync(id: itemId, with: dice(itemId, name: "Saved"))
        try await sut.save()

        try await sut.delete(id: itemId)
        await store.context.perform {
            store.context.rollbackRestoringFlushedOperations()
        }
        try await sut.save()

        #expect(try await sut.fetchIds().isEmpty)
    }

    /// §5.4: the same for a direct replace (`addNew`).
    @Test func directReplaceSurvivesARollbackOfTheSharedContext() async throws {
        let store = try makeStore()
        let sut = DataController(context: store.context, token: NetworkModules.dice.token)
        let itemId = UUID()

        try await sut.replace(id: itemId, with: dice(itemId, name: "New"))
        await store.context.perform {
            store.context.rollbackRestoringFlushedOperations()
        }
        try await sut.save()

        #expect(try await sut.fetchIds() == [itemId])
    }

    /// §5.3: an edit is re-queued by at most `maxRollbackRetries` rollbacks, then discarded,
    /// so a recurring save error can't stall persistence for the whole session.
    @Test func rollbackRetriesAreCapped() async throws {
        let store = try makeStore()
        let sut = DataController(context: store.context, token: NetworkModules.dice.token)
        let itemId = UUID()
        try sut.replaceSync(id: itemId, with: dice(itemId, name: "Failing"))

        for _ in 0...CoreDataModel.maxRollbackRetries {
            try await sut.flushPendingOperations()
            await store.context.perform {
                store.context.rollbackRestoringFlushedOperations()
            }
        }
        try await sut.save()

        #expect(try await sut.fetchIds().isEmpty)
    }

    /// §5.3: the items a failed save names are quarantined; the other edits are retried.
    @Test func itemsNamedByTheSaveErrorAreNotRetried() async throws {
        let store = try makeStore()
        let sut = DataController(context: store.context, token: NetworkModules.dice.token)
        let invalidId = UUID()
        let validId = UUID()
        try sut.replaceSync(id: invalidId, with: dice(invalidId, name: "Invalid"))
        try sut.replaceSync(id: validId, with: dice(validId, name: "Valid"))
        try await sut.flushPendingOperations()

        await store.context.perform {
            let invalidObject = store.context.registeredObjects.first {
                ($0 as? any CoreDataId)?.uuid == invalidId
            }
            let error = NSError(
                domain: NSCocoaErrorDomain,
                code: NSValidationMissingMandatoryPropertyError,
                userInfo: [NSValidationObjectErrorKey: invalidObject as Any]
            )
            store.context.rollbackRestoringFlushedOperations(after: error)
        }
        try await sut.save()

        #expect(try await sut.fetchIds() == [validId])
    }

    /// §5.1: a failed consolidated save re-queues the import's insert; the rollback's delete
    /// (`ItemControllable.deleteForExternalImport`) must keep the second save from committing it.
    @Test func rolledBackImportInsertIsNotCommittedByTheNextSave() async throws {
        let store = try makeStore()
        let sut = DataController(context: store.context, token: NetworkModules.dice.token)
        let importedId = UUID()
        try sut.replaceSync(id: importedId, with: dice(importedId, name: "Imported"))
        sut.markUnsavedInsert(id: importedId)
        try await sut.flushPendingOperations()
        await store.context.perform {
            store.context.rollbackRestoringFlushedOperations()
        }

        await sut.removePendingOperations(for: importedId)
        try await sut.delete(id: importedId)
        try await sut.save()

        #expect(try await sut.fetchIds().isEmpty)
    }

    /// §5.12: a full reconciliation keeps an unsaved local insert listed, not only in `itemData`.
    @Test func reconciliationKeepsUnsavedInsertsListed() async throws {
        let store = try makeStore()
        let root = DiceRootModel.testRoot()
        root.itemController.itemDataModel.dataController = DataController(context: store.context, token: NetworkModules.dice.token)
        let localId = UUID()
        let remoteId = UUID()
        root.itemController.replace(model: dice(localId, name: "Local"), isInsert: true)

        await root.itemController.updates([dice(remoteId, name: "Remote")])

        #expect(Set(root.itemController.itemDataModel.items) == [localId, remoteId])
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
