// @copyright André Trettin

#if canImport(Testing)
import CoreData
import Foundation
import Synchronization
import Testing

@testable import CoreRPG
@testable import PdfRPG

// CODE_AUDIT_TestGaps §3.1: the intake of CloudKit changes. The Pdf module stands in for every
// module: `SyncDataControllable`, `CoreDataChangeObserver` and the context flush ledger are shared
// code, and Pdf is the smallest module with a real Core Data entity (`RPGPdf` with child
// `RPGPdfEntry` rows).

// MARK: - Fake store

private enum FakeStoreError: Error {
    case fetchFailed
}

/// The persisted side of the module: what a fetch of the shared Core Data store returns.
///
/// Not main-actor isolated: the protocol's requirements are nonisolated, so the state sits
/// behind a lock and the tests read and write it through the properties below.
private final class FakePdfStore: DataPersistenceControllable, Sendable {
    private struct State {
        var models: [UUID: PdfModel] = [:]
        var unsavedInserts: Set<UUID> = []
        var failingFetchIds: Set<UUID> = []
        var fetchOrder: [UUID] = []
    }

    private let state = Mutex(State())

    /// What the store holds.
    var models: [UUID: PdfModel] {
        get { state.withLock { $0.models } }
        set { state.withLock { $0.models = newValue } }
    }

    /// Ids of locally created items whose insert is still queued.
    var unsavedInserts: Set<UUID> {
        get { state.withLock { $0.unsavedInserts } }
        set { state.withLock { $0.unsavedInserts = newValue } }
    }

    /// Ids whose next `fetch(id:)` throws once.
    var failingFetchIds: Set<UUID> {
        get { state.withLock { $0.failingFetchIds } }
        set { state.withLock { $0.failingFetchIds = newValue } }
    }

    /// Every id `fetch(id:)` was asked for, in call order.
    var fetchOrder: [UUID] { state.withLock { $0.fetchOrder } }

    func fetch(id: UUID) async throws -> ModelType? {
        let outcome = state.withLock { state -> PdfModel?? in
            state.fetchOrder.append(id)
            if state.failingFetchIds.remove(id) != nil { return nil }
            return .some(state.models[id])
        }
        guard let outcome else { throw FakeStoreError.fetchFailed }
        return outcome
    }

    func fetchAll() async throws -> [any ModelType] { state.withLock { Array($0.models.values) } }
    func fetchIds() async throws -> [UUID] { state.withLock { Array($0.models.keys) } }
    func delete(id: UUID) async throws { state.withLock { _ = $0.models.removeValue(forKey: id) } }
    func batchDelete(ids: [UUID]) async throws { state.withLock { state in ids.forEach { _ = state.models.removeValue(forKey: $0) } } }
    func replaceSync(id: UUID, with viewModel: any ModelType) throws {}
    func replace(id: UUID, with viewModel: any ModelType) async throws {}
    func save() async throws {}
    func flushPendingOperations() async throws {}
    func removePendingOperations(for id: UUID) async {}
    func markUnsavedInsert(id: UUID) { state.withLock { _ = $0.unsavedInserts.insert(id) } }
    func unsavedInsertIds() async -> Set<UUID> { state.withLock { $0.unsavedInserts } }
}

private struct TestSyncController: SyncDataControllable {
    let dataControllable: any DataPersistenceControllable
    let itemControllable: any ItemControllable
    let changeObserver = CoreDataChangeObserver()
}

/// A Pdf module whose "database" is a `FakePdfStore`, with the sync consumer wired the way
/// `PdfRootModel.setUp` wires it.
@MainActor
private struct SyncFixture {
    let itemController = ItemController(config: ModuleConfiguration())
    let store = FakePdfStore()
    let sync: TestSyncController

    init() {
        itemController.itemDataModel.dataController = store
        itemController.itemDataModel.linkRegisterController = LinkRegisterController(root: nil)
        sync = TestSyncController(dataControllable: store, itemControllable: itemController)
    }

    var itemIds: [UUID] { itemController.itemDataModel.items }

    func name(of id: UUID) -> String? {
        (itemController.itemDataModel.itemData[id] as? PdfModel)?.name
    }

    /// An item that is already loaded in memory, as after the first fetch at launch.
    func load(_ model: PdfModel) {
        itemController.resetModel(with: model)
    }

    func reportChange(deleted: [UUID] = [], inserted: [UUID] = [], updated: [UUID] = []) {
        sync.updateFromSync(deletedIds: deleted, insertedIds: inserted, updatedIds: updated)
    }

    func stop() {
        itemController.itemDataModel.syncBatchConsumer?.cancel()
    }
}

/// A model whose registers are stamped after everything created before it, so a merge picks it.
@MainActor
private func newerModel(id: UUID, name: String) -> PdfModel {
    let start = Date.now
    while Date.now.timeIntervalSince(start) < 0.005 {}
    return PdfModel(id: id, name: name)
}

// MARK: - Sync consumer

@MainActor
@Suite("CloudKit sync intake")
struct SyncDataControllerTests {
    @Test("An inserted id is fetched from the store and added to the module")
    func insertedItemIsLoaded() async {
        let fixture = SyncFixture()
        defer { fixture.stop() }
        let id = UUID()
        fixture.store.models[id] = PdfModel(id: id, name: "Remote book")

        fixture.reportChange(inserted: [id])

        #expect(await awaitCondition { fixture.itemIds.contains(id) })
        #expect(fixture.name(of: id) == "Remote book")
    }

    @Test("Change notifications are applied one batch at a time, in the order they arrived")
    func batchesApplyInArrivalOrder() async {
        let fixture = SyncFixture()
        defer { fixture.stop() }
        let ids = (0..<5).map { _ in UUID() }
        for id in ids {
            fixture.store.models[id] = PdfModel(id: id, name: "Book \(id.uuidString.prefix(4))")
        }

        // All batches are queued before the consumer task gets to run.
        for id in ids {
            fixture.reportChange(inserted: [id])
        }

        #expect(await awaitCondition { fixture.itemIds.count == ids.count })
        #expect(fixture.store.fetchOrder == ids)
        #expect(Set(fixture.itemIds) == Set(ids))
    }

    @Test("A batch queued before a data reset is skipped, a later one is applied")
    func batchesQueuedBeforeAResetAreSkipped() async {
        let fixture = SyncFixture()
        defer { fixture.stop() }
        let staleId = UUID()
        let freshId = UUID()
        fixture.store.models[staleId] = PdfModel(id: staleId, name: "Stale")
        fixture.store.models[freshId] = PdfModel(id: freshId, name: "Fresh")

        fixture.reportChange(inserted: [staleId])
        fixture.itemController.itemDataModel.discardQueuedSyncBatches()
        fixture.reportChange(inserted: [freshId])

        #expect(await awaitCondition { fixture.itemIds.contains(freshId) })
        #expect(!fixture.itemIds.contains(staleId))
        #expect(fixture.store.fetchOrder == [freshId])
    }

    @Test("An updated id is merged into the item that is already loaded")
    func updatedItemIsMerged() async {
        let fixture = SyncFixture()
        defer { fixture.stop() }
        let id = UUID()
        fixture.load(PdfModel(id: id, name: "Local name"))
        let loaded = fixture.itemController.itemDataModel.itemData[id] as? PdfModel
        fixture.store.models[id] = newerModel(id: id, name: "Name from another device")

        fixture.reportChange(updated: [id])

        #expect(await awaitCondition { fixture.name(of: id) == "Name from another device" })
        // Merged into the live instance, which open views and editors hold: not replaced.
        #expect(loaded != nil)
        #expect((fixture.itemController.itemDataModel.itemData[id] as? PdfModel) === loaded)
    }

    @Test("An inserted id that is already loaded is merged and listed once")
    func insertOfALoadedIdDoesNotDuplicateIt() async {
        let fixture = SyncFixture()
        defer { fixture.stop() }
        let id = UUID()
        fixture.load(PdfModel(id: id, name: "Imported on this device"))
        fixture.store.models[id] = newerModel(id: id, name: "Imported on another device")

        fixture.reportChange(inserted: [id])

        #expect(await awaitCondition { fixture.name(of: id) == "Imported on another device" })
        #expect(fixture.itemIds.filter { $0 == id }.count == 1)
    }

    @Test("A deletion is found by diffing against the store, not by the reported id")
    func deletionIsDiffedAgainstTheStore() async {
        let fixture = SyncFixture()
        defer { fixture.stop() }
        let deletedRemotely = UUID()
        let kept = UUID()
        fixture.load(PdfModel(id: deletedRemotely, name: "Deleted on another device"))
        fixture.load(PdfModel(id: kept, name: "Kept"))
        fixture.store.models[kept] = PdfModel(id: kept, name: "Kept")

        // Core Data reports a freshly generated id for an object it can no longer resolve.
        fixture.reportChange(deleted: [UUID()])

        #expect(await awaitCondition { !fixture.itemIds.contains(deletedRemotely) })
        #expect(fixture.itemIds == [kept])
    }

    @Test("An item created on this device whose insert is still queued is not taken for a remote deletion")
    func unsavedLocalInsertSurvivesADeletionBatch() async {
        let fixture = SyncFixture()
        defer { fixture.stop() }
        let unsavedId = UUID()
        let deletedRemotely = UUID()
        fixture.load(PdfModel(id: unsavedId, name: "Just created"))
        fixture.load(PdfModel(id: deletedRemotely, name: "Deleted on another device"))
        fixture.store.unsavedInserts = [unsavedId]

        fixture.reportChange(deleted: [UUID()])

        #expect(await awaitCondition { !fixture.itemIds.contains(deletedRemotely) })
        #expect(fixture.itemIds == [unsavedId])
    }

    @Test("A failed fetch reconciles the whole module afterwards")
    func failedFetchTriggersAFullReconciliation() async {
        let fixture = SyncFixture()
        defer { fixture.stop() }
        let reported = UUID()
        let unreported = UUID()
        fixture.store.models[reported] = PdfModel(id: reported, name: "Reported")
        fixture.store.models[unreported] = PdfModel(id: unreported, name: "Never reported")
        fixture.store.failingFetchIds = [reported]

        fixture.reportChange(inserted: [reported])

        // The reported id failed, and a later notification carries only its own ids: only the
        // full reconciliation can load both.
        #expect(await awaitCondition { Set(fixture.itemIds) == [reported, unreported] })
    }
}

// MARK: - Change observer

private final class ChangeRecorder: Sendable {
    struct Change: Sendable {
        let deleted: [UUID]
        let inserted: [UUID]
        let updated: [UUID]
    }

    private let recorded = Mutex<[Change]>([])
    var changes: [Change] { recorded.withLock { $0 } }

    func record(deleted: [UUID], inserted: [UUID], updated: [UUID]) {
        recorded.withLock { $0.append(Change(deleted: deleted, inserted: inserted, updated: updated)) }
    }
}

private struct SyncTestStore {
    let container: NSPersistentContainer
    let context: NSManagedObjectContext

    @MainActor
    init() throws {
        let model = try #require(NSManagedObjectModel.mergedModel(from: [CoreRPG.Resources.bundle, PdfRPG.Resources.bundle]))
        container = NSPersistentContainer(name: "SyncTests-\(UUID().uuidString)", managedObjectModel: model)
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        description.shouldAddStoreAsynchronously = false
        container.persistentStoreDescriptions = [description]
        var loadError: (any Error)?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError { throw loadError }
        context = container.newBackgroundContext()
    }

    /// The Pdf entity of this store's own model. `RPGPdf.entity()` cannot be used: every test
    /// loads its own copy of the model, so Core Data finds no unique match for the class.
    var pdfEntity: NSEntityDescription {
        get throws {
            try #require(container.managedObjectModel.entitiesByName["RPGPdf"])
        }
    }

    /// Saves a Pdf row and returns its object id.
    func insertPdf(uuid: UUID) throws -> NSManagedObjectID {
        try context.performAndWait {
            let pdf = RPGPdf(context: context)
            pdf.uuid = uuid
            try context.save()
            return pdf.objectID
        }
    }

    func insertEntry(uuid: UUID, in pdfObjectId: NSManagedObjectID) throws -> NSManagedObjectID {
        try context.performAndWait {
            let entry = RPGPdfEntry(context: context)
            entry.uuid = uuid
            entry.pdf = try context.existingObject(with: pdfObjectId) as? RPGPdf
            try context.save()
            return entry.objectID
        }
    }

    func post(inserted: Set<NSManagedObjectID> = [], updated: Set<NSManagedObjectID> = [], deleted: Set<NSManagedObjectID> = []) {
        var userInfo: [String: Any] = [:]
        if !inserted.isEmpty { userInfo[NSInsertedObjectIDsKey] = inserted }
        if !updated.isEmpty { userInfo[NSUpdatedObjectIDsKey] = updated }
        if !deleted.isEmpty { userInfo[NSDeletedObjectIDsKey] = deleted }
        NotificationCenter.default.post(
            name: NSManagedObjectContext.didMergeChangesObjectIDsNotification,
            object: context,
            userInfo: userInfo
        )
    }
}

@MainActor
@Suite("Core Data change observer")
struct CoreDataChangeObserverTests {
    private func observe(_ store: SyncTestStore) throws -> (CoreDataChangeObserver, ChangeRecorder) {
        let recorder = ChangeRecorder()
        let sut = CoreDataChangeObserver()
        sut.observeCoreDataChanges(from: store.context, entity: try store.pdfEntity) { deleted, inserted, updated in
            recorder.record(deleted: deleted, inserted: inserted, updated: updated)
        }
        return (sut, recorder)
    }

    @Test("Reports the ids of inserted and updated rows of its entity")
    func reportsInsertedAndUpdatedIds() throws {
        let store = try SyncTestStore()
        let insertedId = UUID()
        let updatedId = UUID()
        let inserted = try store.insertPdf(uuid: insertedId)
        let updated = try store.insertPdf(uuid: updatedId)
        let (sut, recorder) = try observe(store)
        withExtendedLifetime(sut) {
            store.post(inserted: [inserted], updated: [updated])
        }

        let change = try #require(recorder.changes.first)
        #expect(recorder.changes.count == 1)
        #expect(change.inserted == [insertedId])
        #expect(change.updated == [updatedId])
        #expect(change.deleted.isEmpty)
    }

    @Test("Rows of another entity are not reported")
    func ignoresOtherEntities() throws {
        let store = try SyncTestStore()
        let pdf = try store.insertPdf(uuid: UUID())
        let entry = try store.insertEntry(uuid: UUID(), in: pdf)
        let (sut, recorder) = try observe(store)
        withExtendedLifetime(sut) {
            store.post(inserted: [entry], updated: [entry])
        }

        // Nothing of the observed entity changed, so the handler is not called at all.
        #expect(recorder.changes.isEmpty)
    }

    @Test("A notification without object ids does not call the handler")
    func ignoresEmptyNotifications() throws {
        let store = try SyncTestStore()
        let (sut, recorder) = try observe(store)
        withExtendedLifetime(sut) {
            store.post()
        }

        #expect(recorder.changes.isEmpty)
    }

    @Test("A deleted row that can no longer be resolved is reported with a placeholder id")
    func deletedRowIsReportedWithAPlaceholder() throws {
        let store = try SyncTestStore()
        let objectId = try store.insertPdf(uuid: UUID())
        try store.context.performAndWait {
            let object = try store.context.existingObject(with: objectId)
            store.context.delete(object)
            try store.context.save()
        }
        let (sut, recorder) = try observe(store)
        withExtendedLifetime(sut) {
            store.post(deleted: [objectId])
        }

        // The consumer diffs against the store, so the observer only has to say that a
        // deletion happened; whether the id resolves depends on Core Data's faulting.
        let change = try #require(recorder.changes.first)
        #expect(change.deleted.count == 1)
        #expect(change.inserted.isEmpty)
        #expect(change.updated.isEmpty)
    }

    @Test("Stops reporting once the observer is released")
    func releasedObserverStopsReporting() throws {
        let store = try SyncTestStore()
        let objectId = try store.insertPdf(uuid: UUID())
        let recorder = ChangeRecorder()
        do {
            let sut = CoreDataChangeObserver()
            sut.observeCoreDataChanges(from: store.context, entity: try store.pdfEntity) { deleted, inserted, updated in
                recorder.record(deleted: deleted, inserted: inserted, updated: updated)
            }
        }

        store.post(inserted: [objectId])

        #expect(recorder.changes.isEmpty)
    }
}

// MARK: - Failing item ids

@MainActor
@Suite("Failing items of a save error")
struct FailingItemIdsTests {
    @Test("A child row that fails validation names the item that owns it")
    func failingChildNamesItsOwner() throws {
        let store = try SyncTestStore()
        let pdfId = UUID()
        let entryId = UUID()
        let pdfObjectId = try store.insertPdf(uuid: pdfId)
        let entryObjectId = try store.insertEntry(uuid: entryId, in: pdfObjectId)

        let ids = try store.context.performAndWait {
            let entry = try store.context.existingObject(with: entryObjectId)
            let error = NSError(domain: NSCocoaErrorDomain, code: NSValidationStringTooShortError, userInfo: [NSValidationObjectErrorKey: entry])
            return NSManagedObjectContext.failingItemIds(in: error)
        }

        // The child has its own id, which never equals the operation id of its item.
        #expect(ids == [entryId, pdfId])
    }

    @Test("Detailed errors of a multi-failure save are all collected")
    func detailedErrorsAreCollected() throws {
        let store = try SyncTestStore()
        let firstId = UUID()
        let secondId = UUID()
        let firstObjectId = try store.insertPdf(uuid: firstId)
        let secondObjectId = try store.insertPdf(uuid: secondId)

        let ids = try store.context.performAndWait {
            let detailed = try [firstObjectId, secondObjectId].map { objectId in
                NSError(domain: NSCocoaErrorDomain, code: NSValidationMissingMandatoryPropertyError, userInfo: [
                    NSValidationObjectErrorKey: try store.context.existingObject(with: objectId)
                ])
            }
            let error = NSError(domain: NSCocoaErrorDomain, code: NSValidationMultipleErrorsError, userInfo: [NSDetailedErrorsKey: detailed])
            return NSManagedObjectContext.failingItemIds(in: error)
        }

        #expect(ids == [firstId, secondId])
    }

    @Test("An error that names no object names no item")
    func errorWithoutObjectsNamesNothing() {
        let error = NSError(domain: NSCocoaErrorDomain, code: NSPersistentStoreSaveError)

        #expect(NSManagedObjectContext.failingItemIds(in: error).isEmpty)
    }
}
#endif
