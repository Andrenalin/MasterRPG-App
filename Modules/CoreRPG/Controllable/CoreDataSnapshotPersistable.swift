// @copyright André Trettin

import Foundation
import CoreData
import Observation

/// Snapshot-based persistence for modules whose domain models are @MainActor.
///
/// The Core Data context queue only ever sees the `Snapshot` value type:
/// `mapSnapshot`/`applySnapshot` run on the context queue, while model ⇄ snapshot
/// conversion (`makeModel`/`makeSnapshot`) is pinned to the MainActor. This replaces
/// the copy-before-crossing convention of `CoreDataPersistable` with compiler-checked
/// Sendable boundaries.
public protocol CoreDataSnapshotPersistable: DataPersistenceControllable {
    associatedtype DataType: NSManagedObject & CoreDataId
    associatedtype Model: ModelType
    associatedtype Snapshot: Sendable

    var dataController: CoreDataController<Model, DataType> { get }
    var token: String { get }

    /// Context queue: managed object → snapshot.
    @Sendable func mapSnapshot(_ data: DataType, token: String) -> Snapshot
    /// Context queue: snapshot → managed object.
    @Sendable func applySnapshot(_ snapshot: Snapshot, into data: DataType)
    /// MainActor: snapshot → domain model.
    @MainActor func makeModel(from snapshot: Snapshot) -> Model
    /// MainActor: domain model → snapshot.
    @MainActor func makeSnapshot(from model: Model) -> Snapshot
}

public extension CoreDataSnapshotPersistable {
    @MainActor
    func replaceSync(id: UUID, with viewModel: any ModelType) throws {
        guard let viewModel = viewModel as? Model else { return }
        let snapshot = makeSnapshot(from: viewModel)
        dataController.queueReplace(uuid: id, snapshot: snapshot, updater: applySnapshot(_:into:))
    }

    func removePendingOperations(for id: UUID) async {
        dataController.model.removePendingOperations(for: id)
    }

    func replace(id: UUID, with viewModel: any ModelType) async throws {
        guard let viewModel = viewModel as? Model else { return }
        // `makeSnapshot(from:)` is itself `@MainActor` — `await` alone hops there, no
        // `MainActor.run` wrapper needed.
        let snapshot = await makeSnapshot(from: viewModel)
        try await dataController.replace(uuid: id, snapshot: snapshot, updater: applySnapshot(_:into:))
    }

    func fetch(id: UUID) async throws -> ModelType? {
        let token = self.token
        guard let snapshot = try await dataController.fetchSnapshot(uuid: id, mapper: { self.mapSnapshot($0, token: token) }) else { return nil }
        return await makeModel(from: snapshot)
    }

    func fetch() async throws -> [Model] {
        let token = self.token
        let snapshots = try await dataController.fetchSnapshots { self.mapSnapshot($0, token: token) }
        // A plain `.map` closure can't be `async`, so this can't collapse to a single
        // `await`-prefixed expression the way the single-snapshot `fetch(id:)` above does;
        // loop with one `await makeModel(from:)` per snapshot instead of batching the whole
        // conversion inside `MainActor.run`.
        var models: [Model] = []
        models.reserveCapacity(snapshots.count)
        for snapshot in snapshots {
            models.append(await makeModel(from: snapshot))
        }
        return models
    }

    func fetchAll() async throws -> [any ModelType] {
        try await fetch()
    }

    func fetchIds() async throws -> [UUID] {
        try await dataController.fetchIds()
    }

    func delete(id: UUID) async throws {
        try await dataController.delete(uuid: id)
    }

    func batchDelete(ids: [UUID]) async throws {
        try await dataController.batchDelete(uuids: ids)
    }

    func save() async throws {
        try await dataController.save()
    }

    func flushPendingOperations() async throws {
        try await dataController.flushPendingOperations()
    }

    func tags(from model: String?) -> [String] {
        guard let model else { return [] }
        return model.components(separatedBy: ",").compactMap {
            let tag = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            if tag.isEmpty {
                return nil
            }
            return tag
        }
    }
}
