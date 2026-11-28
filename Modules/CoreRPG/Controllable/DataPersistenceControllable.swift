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
    /// Marks `id` as an item created on this device whose insert is queued but not yet
    /// committed. See CODE_AUDIT_18 §5.2.
    @MainActor func markUnsavedInsert(id: UUID)
    /// Ids of locally created items whose insert is not committed yet. The sync-deletion
    /// diff must not treat these as remotely deleted. See CODE_AUDIT_18 §5.2.
    func unsavedInsertIds() async -> Set<UUID>
    /// Whether a local edit of `id` is queued (or flushed) but not committed yet.
    /// See CODE_AUDIT_Edit_Save §3.1.
    func hasPendingOperation(for id: UUID) async -> Bool
}

public extension DataPersistenceControllable {
    @MainActor func markUnsavedInsert(id: UUID) {}
    func unsavedInsertIds() async -> Set<UUID> { [] }
    func hasPendingOperation(for id: UUID) async -> Bool { false }
}
