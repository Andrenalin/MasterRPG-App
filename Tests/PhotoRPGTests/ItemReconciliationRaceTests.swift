// @copyright André Trettin

#if canImport(Testing)
import CoreData
import Foundation
import Testing

@testable import CoreRPG
@testable import PhotoRPG

/// CODE_AUDIT_26 §5.49 / §10.1: a full reconciliation that awaits must not drop or delete an item
/// created while it waits.
@Suite(.serialized)
@MainActor
struct ItemReconciliationRaceTests {
    @Test("An item added while the reconciliation awaits is kept and not deleted")
    func itemAddedDuringReconciliationSurvives() async throws {
        let store = try InMemoryStore(bundles: [CoreRPG.Resources.bundle, PhotoRPG.Resources.bundle])
        let root = PhotoRootModel.persistentTestRoot(context: store.context)
        let keptId = await root.itemController.addNew(type: .item)
        await root.itemController.save()
        let stored = try #require(root.itemController.itemSync(for: keptId, noGame: true))

        // The reconciliation suspends inside `unsavedInsertIds()`, after it noted the known ids.
        let gate = ReconciliationGate()
        let base = try #require(root.itemController.itemDataModel.dataController)
        root.itemController.itemDataModel.dataController = GatedPersistence(base: base, gate: gate)

        let reconcile = Task { @MainActor in
            await root.itemController.updates([stored])
        }
        await gate.waitUntilEntered()
        let lateId = UUID()
        root.itemController.resetModel(with: PhotoModel(id: lateId, name: "Late"))
        await gate.open()
        await reconcile.value

        #expect(root.itemController.itemDataModel.items.contains(lateId))
        #expect(root.itemController.itemSync(for: lateId, noGame: true) != nil)
        #expect(root.itemController.itemDataModel.items.contains(keptId))
    }

    @Test("An item that is gone from the store and was never inserted locally is removed")
    func missingItemIsRemoved() async throws {
        let store = try InMemoryStore(bundles: [CoreRPG.Resources.bundle, PhotoRPG.Resources.bundle])
        let root = PhotoRootModel.persistentTestRoot(context: store.context)
        let keptId = await root.itemController.addNew(type: .item)
        let goneId = await root.itemController.addNew(type: .item)
        await root.itemController.save()
        let stored = try #require(root.itemController.itemSync(for: keptId, noGame: true))
        // The insert of `goneId` committed, so it is no unsaved insert; the fetch no longer has it.
        await root.itemController.updates([stored])

        #expect(root.itemController.itemDataModel.items.contains(keptId))
        #expect(!root.itemController.itemDataModel.items.contains(goneId))
    }
}

/// Holds a reconciliation at its first suspension until the test lets it go.
private actor ReconciliationGate {
    private var hasEntered = false
    private var isOpen = false
    private var enterWaiters: [CheckedContinuation<Void, Never>] = []
    private var openWaiters: [CheckedContinuation<Void, Never>] = []

    func pass() async {
        hasEntered = true
        for waiter in enterWaiters { waiter.resume() }
        enterWaiters = []
        guard !isOpen else { return }
        await withCheckedContinuation { openWaiters.append($0) }
    }

    func waitUntilEntered() async {
        guard !hasEntered else { return }
        await withCheckedContinuation { enterWaiters.append($0) }
    }

    func open() {
        isOpen = true
        for waiter in openWaiters { waiter.resume() }
        openWaiters = []
    }
}

/// Forwards to the real persistence; only `unsavedInsertIds()` waits on the gate.
private struct GatedPersistence: DataPersistenceControllable {
    let base: any DataPersistenceControllable
    let gate: ReconciliationGate

    func fetch(id: UUID) async throws -> ModelType? { try await base.fetch(id: id) }
    func fetchAll() async throws -> [any ModelType] { try await base.fetchAll() }
    func fetchIds() async throws -> [UUID] { try await base.fetchIds() }
    func delete(id: UUID) async throws { try await base.delete(id: id) }
    func batchDelete(ids: [UUID]) async throws { try await base.batchDelete(ids: ids) }
    @MainActor func replaceSync(id: UUID, with viewModel: any ModelType) throws { try base.replaceSync(id: id, with: viewModel) }
    func replace(id: UUID, with viewModel: any ModelType) async throws { try await base.replace(id: id, with: viewModel) }
    func save() async throws { try await base.save() }
    func flushPendingOperations() async throws { try await base.flushPendingOperations() }
    func removePendingOperations(for id: UUID) async { await base.removePendingOperations(for: id) }
    @MainActor func markUnsavedInsert(id: UUID) { base.markUnsavedInsert(id: id) }
    func unsavedInsertIds() async -> Set<UUID> {
        await gate.pass()
        return await base.unsavedInsertIds()
    }
}
#endif
