// @copyright André Trettin

import Foundation
import CoreData
import Observation

public protocol DataPersistenceControllable: Sendable {
    func fetch(id: UUID) async throws -> ModelType?
    func delete(id: UUID) async throws
    func batchDelete(ids: [UUID]) async throws
    func replaceSync(id: UUID, with viewModel: any ModelType) throws
    func replace(id: UUID, with viewModel: any ModelType) async throws
    func save() async throws
    /// Flush pending operations into the context without calling `context.save()`.
    /// Called by `AdventureRootModel.save()` for each module root before the single consolidated save.
    func flushPendingOperations() async throws
}
