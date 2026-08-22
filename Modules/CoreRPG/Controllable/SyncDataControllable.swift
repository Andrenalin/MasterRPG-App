// @copyright André Trettin

import Foundation
import CoreData
import Observation
import os.log

public protocol SyncDataControllable: Sendable {
    var dataControllable: any DataPersistenceControllable { get }
    var itemControllable: any ItemControllable { get }
    var changeObserver: CoreDataChangeObserver { get }
}

// MARK: - Shared change-observer wiring

public extension SyncDataControllable {
    /// Wires up Core Data change observation for `entity` on the already-created
    /// `changeObserver`. Every conforming module's own `SyncDataController.init` calls this
    /// once — as its last statement, after `dataControllable`/`itemControllable`/`changeObserver`
    /// are all already assigned — instead of hand-duplicating this identical wiring call 12
    /// times. (It can't be folded into `changeObserver`'s own assignment: calling any
    /// instance/extension method on `self` mid-initializer requires every stored property,
    /// including the one being assigned, to already have a value.) The only per-module
    /// difference is the Core Data `entity` being observed. See CODE_AUDIT §9.2.
    func startSyncObservation(context: NSManagedObjectContext, entity: NSEntityDescription) {
        changeObserver.observeCoreDataChanges(from: context, entity: entity, handler: updateFromSync(deletedIds:insertedIds:updatedIds:))
    }
}

// MARK: Core Data --> CloudKit Sync

public extension SyncDataControllable {
    /// Returns the running sync task so the caller can store/cancel it — this itself stays
    /// non-actor-isolated so the task keeps running off the main actor, same as before.
    nonisolated func start() -> Task<Void, Never> {
        Task(priority: .userInitiated) {
            await fetchUpdates()
        }
    }

    @Sendable
    func updateFromSync(deletedIds: [UUID], insertedIds: [UUID], updatedIds: [UUID]) {
        Task { @MainActor in
            // Cancel any still-in-flight sync from a previous notification so overlapping
            // CloudKit change batches for this module can't race each other applying
            // deletes/inserts/updates out of order — mirrors the cancel-and-replace
            // pattern `FolderListControllable` already uses for its own debounced work.
            // See CODE_AUDIT_EditItem §3.2.
            itemControllable.itemDataModel.pendingSyncTask?.cancel()
            itemControllable.itemDataModel.pendingSyncTask = Task(priority: .userInitiated) {
                do {
                    try Task.checkCancellation()
                    await CloudKitOperationCounter.shared.recordOperation(
                        function: "SyncDataControllable.updateFromSync(deleted:\(deletedIds.count) inserted:\(insertedIds.count) updated:\(updatedIds.count))",
                        file: "SyncDataControllable.swift"
                    )

                    // Process deletions — act directly on the reported ids instead of fetching
                    // every id in the store and diffing against the full in-memory set; that
                    // O(n) full-table reconciliation is reserved for `fetchUpdates()`, which
                    // already runs once at `start()` and would catch any deletion this misses.
                    for deletedId in deletedIds {
                        try Task.checkCancellation()
                        await itemControllable.delete(itemId: deletedId, withFileData: false, withDatabase: false)
                    }

                    // Process insertions
                    // The data is ALREADY in Core Data (we're fetching from it!)
                    // We only need to update in-memory models, NOT save back to database
                    for insertedId in insertedIds {
                        try Task.checkCancellation()
                        guard let model = try await dataControllable.fetch(id: insertedId) else { continue }
                        // `resetModel(with:)` is itself `@MainActor` — `await` alone hops, same as
                        // `delete(itemId:...)` above; no `MainActor.run` wrapper needed.
                        itemControllable.resetModel(with: model)
                    }

                    // Process updates
                    for updatedId in updatedIds {
                        try Task.checkCancellation()
                        guard let model = try await dataControllable.fetch(id: updatedId) else { continue }
                        // Use mergeUpdates to avoid database writes during sync
                        itemControllable.mergeUpdates(model: model)
                    }
                } catch {
                    // Sync errors are non-fatal; the next CloudKit notification will retry —
                    // but log so a merge that keeps failing (rather than self-healing on the
                    // next notification) is actually diagnosable. (Cancellation surfaces here
                    // too, as `CancellationError` — expected when a newer batch superseded
                    // this one, not itself worth alarming about, but harmless to log.)
                    Logger.syncDataControllable.error(
                        "updateFromSync(deleted:\(deletedIds.count) inserted:\(insertedIds.count) updated:\(updatedIds.count)) failed: \(error.localizedDescription, privacy: .public)"
                    )
                }
            }
        }
    }

    private func fetchUpdates() async {
        do {
            let newItems = try await dataControllable.fetchAll()
            await itemControllable.updates(newItems)
        } catch {
            // Mirrors `updateFromSync`'s logging above — this full-table reconciliation
            // only runs once, at `start()`, so a failure here otherwise leaves no trace
            // of why items never loaded at launch. See CODE_AUDIT_EditItem §5.9.
            Logger.syncDataControllable.error("fetchUpdates() failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
