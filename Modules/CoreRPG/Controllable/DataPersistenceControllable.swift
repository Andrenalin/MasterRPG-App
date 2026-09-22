// @copyright André Trettin

import Foundation
import CoreData
import Observation

public protocol DataPersistenceControllable: Sendable {
    func fetch(id: UUID) async throws -> ModelType?
    func fetchAll() async throws -> [any ModelType]
    func fetchIds() async throws -> [UUID]
    func delete(id: UUID) async throws
    func batchDelete(ids: [UUID]) async throws
    /// @MainActor: implementations that snapshot a @MainActor model synchronously
    /// need main-actor isolation; the only caller (ItemControllable.replace) is
    /// already @MainActor. Nonisolated witnesses remain valid.
    @MainActor func replaceSync(id: UUID, with viewModel: any ModelType) throws
    func replace(id: UUID, with viewModel: any ModelType) async throws
    func save() async throws
    /// Flush pending operations into the context without calling `context.save()`.
    /// Called by `AdventureRootModel.save()` for each module root before the single consolidated save.
    func flushPendingOperations() async throws
    /// Drops any not-yet-flushed queued edit for `id`. Called on every item delete
    /// (local or sync-reported) so a pending edit queued just before the deletion
    /// can't resurrect the item on the next flush. See CODE_AUDIT_17 §5.7.
    func removePendingOperations(for id: UUID) async
}
