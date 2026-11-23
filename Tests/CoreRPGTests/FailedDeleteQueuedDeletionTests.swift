// @copyright André Trettin

import Foundation
import Testing

@testable import CoreRPG

/// CODE_AUDIT_28 §5.5: a failed database delete restored the item in memory but left its
/// deletion queued, so the next save removed the row the item was restored for.
@Suite("Failed delete keeps no queued deletion")
@MainActor
struct FailedDeleteQueuedDeletionTests {
    private final class RecordingPersistence: DataPersistenceControllable, @unchecked Sendable {
        private(set) var events: [String] = []
        func fetch(id: UUID) async throws -> ModelType? { nil }
        func fetchAll() async throws -> [any ModelType] { [] }
        func fetchIds() async throws -> [UUID] { [] }
        func delete(id: UUID) async throws {
            events.append("delete")
            throw StoreFailure()
        }
        func batchDelete(ids: [UUID]) async throws {}
        @MainActor func replaceSync(id: UUID, with viewModel: any ModelType) throws {}
        func replace(id: UUID, with viewModel: any ModelType) async throws {}
        func save() async throws {}
        func flushPendingOperations() async throws {}
        func removePendingOperations(for id: UUID) async { events.append("remove") }
    }

    private struct StoreFailure: Error {}

    private func rootWithItem(_ persistence: RecordingPersistence) -> (ItemRootController, UUID) {
        let root = ItemRootController.previewFixture(dataControllable: persistence)
        let itemId = UUID()
        root.itemControllable.resetModel(with: FakeItemModel(id: itemId, name: "Kept", category: .entry))
        return (root, itemId)
    }

    @Test("The deletion a failed delete left queued is dropped, the item stays")
    func failedDeleteDropsQueuedDeletion() async {
        let persistence = RecordingPersistence()
        let (root, itemId) = rootWithItem(persistence)

        await root.itemControllable.delete(itemId: itemId)

        #expect(root.itemControllable.itemSync(for: itemId) != nil)
        #expect(persistence.events.last == "remove", "the queued deletion would remove the row at the next save: \(persistence.events)")
    }

    @Test("A failed import rollback drops the queued deletion as well")
    func failedExternalImportDeleteDropsQueuedDeletion() async {
        let persistence = RecordingPersistence()
        let (root, itemId) = rootWithItem(persistence)

        await #expect(throws: StoreFailure.self) {
            try await root.itemControllable.deleteForExternalImport(itemId: itemId)
        }

        #expect(root.itemControllable.itemSync(for: itemId) != nil)
        #expect(persistence.events.last == "remove", "\(persistence.events)")
    }
}
