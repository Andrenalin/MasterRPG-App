// @copyright André Trettin

#if canImport(Testing)
import CoreData
import Foundation
import Testing

@testable import CoreRPG

/// CODE_AUDIT_TestGaps §3.1: every module flushes into one shared context and any module can
/// save or roll it back. The ledger tells each module's queue which of the two happened, so a
/// flushed edit is forgotten only once it is committed and is re-queued (not lost) after a
/// rollback. See CODE_AUDIT_18 §5.3, CODE_AUDIT_19 §5.3 and §3.7.
@Suite("Context flush ledger")
struct ContextFlushLedgerTests {
    private let ledger = ContextFlushLedger.shared

    /// A private-queue context on an empty in-memory model. The ledger keys its queues by the
    /// context's identity, so every test uses a context of its own and runs in parallel.
    private func makeContext() throws -> NSManagedObjectContext {
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: NSManagedObjectModel())
        try coordinator.addPersistentStore(ofType: NSInMemoryStoreType, configurationName: nil, at: nil, options: nil)
        let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        return context
    }

    private func operation(_ id: UUID) -> PendingOperation {
        PendingOperation(id: id, model: "edit", updater: { _, _ in })
    }

    /// Queues and flushes `ids` the way `flushPendingOperations` does: out of the queue, onto the
    /// context, recorded as in flight until the context commits or rolls back.
    private func flush(_ ids: [UUID], in model: CoreDataModel) {
        for id in ids {
            model.addPendingOperation(operation(id))
        }
        model.markInFlight(model.clearPendingOperations())
    }

    private func didSave(_ context: NSManagedObjectContext) {
        NotificationCenter.default.post(name: .NSManagedObjectContextDidSave, object: context)
    }

    @Test("A save of the shared context commits the flushed edits of every module")
    func saveCommitsEveryRegisteredModel() throws {
        let context = try makeContext()
        defer { ledger.unregister(context) }
        let first = CoreDataModel()
        let second = CoreDataModel()
        ledger.register(first, for: context)
        ledger.register(second, for: context)
        flush([UUID()], in: first)
        flush([UUID()], in: second)

        didSave(context)

        // Committed edits are forgotten: a later rollback has nothing to re-queue.
        first.restoreInFlight()
        second.restoreInFlight()
        #expect(first.clearPendingOperations().isEmpty)
        #expect(second.clearPendingOperations().isEmpty)
    }

    @Test("A save of another context does not commit the flushed edits")
    func saveOfAnotherContextIsIgnored() throws {
        let context = try makeContext()
        let otherContext = try makeContext()
        defer { ledger.unregister(context) }
        let model = CoreDataModel()
        ledger.register(model, for: context)
        let id = UUID()
        flush([id], in: model)

        didSave(otherContext)

        // Still in flight: a rollback puts the edit back in the queue.
        model.restoreInFlight()
        #expect(model.clearPendingOperations().map(\.id) == [id])
    }

    @Test("A rollback re-queues the flushed edits of every module, oldest first")
    func rollbackRequeuesFlushedEdits() throws {
        let context = try makeContext()
        defer { ledger.unregister(context) }
        let first = CoreDataModel()
        let second = CoreDataModel()
        ledger.register(first, for: context)
        ledger.register(second, for: context)
        let firstIds = [UUID(), UUID()]
        let secondId = UUID()
        flush(firstIds, in: first)
        flush([secondId], in: second)

        context.performAndWait {
            context.rollbackRestoringFlushedOperations()
        }

        #expect(first.hasRetryingOperations)
        #expect(second.hasRetryingOperations)
        let firstPending = first.clearPendingOperations()
        #expect(firstPending.map(\.id) == firstIds)
        #expect(firstPending.allSatisfy { $0.rollbackCount == 1 })
        #expect(second.clearPendingOperations().map(\.id) == [secondId])
    }

    @Test("A rollback that names the failing items discards only those and blames only them")
    func rollbackDiscardsTheNamedFailingItems() throws {
        let context = try makeContext()
        defer { ledger.unregister(context) }
        let model = CoreDataModel()
        ledger.register(model, for: context)
        let failingId = UUID()
        let innocentId = UUID()
        flush([failingId, innocentId], in: model)

        ledger.didRollBack(context, failingIds: [failingId])

        let pending = model.clearPendingOperations()
        #expect(pending.map(\.id) == [innocentId])
        // With the failing item identified the others are not blamed, so a bad item cannot use up
        // their retries.
        #expect(pending.first?.rollbackCount == 0)
    }

    @Test("An edit that keeps being rolled back is discarded after the retry cap")
    func rollbackRetriesAreCapped() throws {
        let context = try makeContext()
        defer { ledger.unregister(context) }
        let model = CoreDataModel()
        ledger.register(model, for: context)
        let id = UUID()
        flush([id], in: model)

        // Without an identified culprit every rollback counts against every flushed edit.
        for attempt in 1...CoreDataModel.maxRollbackRetries {
            ledger.didRollBack(context)
            let pending = model.clearPendingOperations()
            #expect(pending.map(\.id) == [id], "attempt \(attempt) must still re-queue the edit")
            model.markInFlight(pending)
        }

        ledger.didRollBack(context)

        #expect(model.clearPendingOperations().isEmpty)
        #expect(!model.hasRetryingOperations)
    }

    @Test("An unregistered context no longer commits or re-queues")
    func unregisterStopsTracking() throws {
        let context = try makeContext()
        let model = CoreDataModel()
        ledger.register(model, for: context)
        let id = UUID()
        flush([id], in: model)

        ledger.unregister(context)
        didSave(context)
        context.performAndWait {
            context.rollbackRestoringFlushedOperations()
        }

        // Neither the save nor the rollback reached the model: the edit is still in flight.
        #expect(model.clearPendingOperations().isEmpty)
        model.restoreInFlight()
        #expect(model.clearPendingOperations().map(\.id) == [id])
    }
}
#endif
