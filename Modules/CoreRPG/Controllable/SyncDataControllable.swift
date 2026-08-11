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
        Task(priority: .userInitiated) {
            do {
                await CloudKitOperationCounter.shared.recordOperation(
                    function: "SyncDataControllable.updateFromSync(deleted:\(deletedIds.count) inserted:\(insertedIds.count) updated:\(updatedIds.count))",
                    file: "SyncDataControllable.swift"
                )

                // Process deletions — act directly on the reported ids instead of fetching
                // every id in the store and diffing against the full in-memory set; that
                // O(n) full-table reconciliation is reserved for `fetchUpdates()`, which
                // already runs once at `start()` and would catch any deletion this misses.
                for deletedId in deletedIds {
                    await itemControllable.delete(itemId: deletedId, withFileData: false, withDatabase: false)
                }

                // Process insertions
                // The data is ALREADY in Core Data (we're fetching from it!)
                // We only need to update in-memory models, NOT save back to database
                for insertedId in insertedIds {
                    guard let model = try await dataControllable.fetch(id: insertedId) else { continue }
                    await MainActor.run {
                        itemControllable.resetModel(with: model)
                    }
                }

                // Process updates
                for updatedId in updatedIds {
                    guard let model = try await dataControllable.fetch(id: updatedId) else { continue }
                    // Use mergeUpdates to avoid database writes during sync
                    await MainActor.run {
                        itemControllable.mergeUpdates(model: model)
                    }
                }
            } catch {
                // Sync errors are non-fatal; the next CloudKit notification will retry —
                // but log so a merge that keeps failing (rather than self-healing on the
                // next notification) is actually diagnosable.
                Logger.syncDataControllable.error(
                    "updateFromSync(deleted:\(deletedIds.count) inserted:\(insertedIds.count) updated:\(updatedIds.count)) failed: \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }
    
    private func fetchUpdates() async {
        guard let newItems = try? await dataControllable.fetchAll() else { return }
        await itemControllable.updates(newItems)
    }
}
