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
        // Registered synchronously so `DatabaseReadiness` can't report ready before this
        // module's items are loaded. See CODE_AUDIT_18 §3.2.
        let loadToken = InitialLoadTracker.shared.begin()
        return Task(priority: .userInitiated) {
            await fetchUpdates()
            await InitialLoadTracker.shared.end(loadToken)
        }
    }

    @Sendable
    func updateFromSync(deletedIds: [UUID], insertedIds: [UUID], updatedIds: [UUID]) {
        // Queued synchronously, in the order the notifications arrive, and applied by one
        // consumer task. Previously each notification started a task that chained itself onto
        // `pendingSyncTask`, which only kept arrival order if those tasks happened to run
        // first-in, first-out. See CODE_AUDIT §3.1, CODE_AUDIT_Folder §3.19.
        let dataModel = itemControllable.itemDataModel
        dataModel.enqueueSyncBatch(deletedIds: deletedIds, insertedIds: insertedIds, updatedIds: updatedIds)
        Task { @MainActor in
            startSyncConsumerIfNeeded()
        }
    }

    @MainActor private func startSyncConsumerIfNeeded() {
        let dataModel = itemControllable.itemDataModel
        guard dataModel.syncBatchConsumer == nil else { return }
        dataModel.syncBatchConsumer = Task(priority: .userInitiated) { @MainActor in
            for await batch in dataModel.syncBatches {
                guard batch.sequence > dataModel.discardedSyncBatchSequence else { continue }
                // A bulk import or repair holds the data-mutation lock; apply after it instead
                // of interleaving with its writes. See CODE_AUDIT_Folder §3.5.
                await DataMutationCoordinator.shared.waitUntilIdle()
                guard batch.sequence > dataModel.discardedSyncBatchSequence else { continue }
                await apply(batch)
            }
        }
    }

    @MainActor private func apply(_ batch: SyncBatch) async {
        // The data controller of the store that is current now, not this controller's own.
        // The data model keeps one consumer for its lifetime (cancelling it would end the batch
        // stream), so after a store swap the consumer still runs on the controller of the
        // previous store: its fetches came back empty, and its deletion diff removed the new
        // store's items from the lists. See CODE_AUDIT_21 §3.1.
        guard let dataControllable = itemControllable.dataControllable else { return }

        await CloudKitOperationCounter.shared.recordOperation(
            function: "SyncDataControllable.updateFromSync(deleted:\(batch.deletedIds.count) inserted:\(batch.insertedIds.count) updated:\(batch.updatedIds.count))",
            file: "SyncDataControllable.swift"
        )

        // Process deletions — diff the reported ids against Core Data's actual
        // current ids rather than trusting `deletedIds` directly.
        // `CoreDataChangeObserver` can report a placeholder (freshly-generated,
        // meaningless) UUID for a deleted object it can no longer resolve once
        // Core Data has already turned it into an unfulfillable fault — acting on
        // that placeholder directly is a guaranteed no-op, silently dropping the
        // deletion. Diffing against a fresh id fetch is what the producer's own
        // contract ("consumers diff against fetched ids") assumes. See CODE_AUDIT §3.2.
        //
        // A failed id fetch skips only this diff: the inserts and updates below still
        // apply, and a full reconciliation afterwards catches the deletions. A later
        // notification carries only its own ids, so it would never retry them.
        // See CODE_AUDIT_19 §5.11.
        var needsReconciliation = false
        if !batch.deletedIds.isEmpty {
            do {
                // An item created on this device whose insert is still queued is not in
                // Core Data yet either: it must not be mistaken for a remote deletion, or
                // deleting it would also drop its queued insert for good. See CODE_AUDIT_18 §5.2.
                // Read before and after the fetch: an insert that commits while the fetch runs
                // is in neither the fetch nor a later read alone. See CODE_AUDIT_Folder §3.10.
                let unsavedBeforeFetch = await dataControllable.unsavedInsertIds()
                let currentIds = Set(try await dataControllable.fetchIds())
                let unsavedInsertIds = unsavedBeforeFetch.union(await dataControllable.unsavedInsertIds())
                let staleIds = itemControllable.itemDataModel.items.filter {
                    !currentIds.contains($0) && !unsavedInsertIds.contains($0)
                }
                for staleId in staleIds {
                    await itemControllable.delete(itemId: staleId, withFileData: false, withDatabase: false)
                }
            } catch {
                Logger.syncDataControllable.error("updateFromSync deletion diff failed, reconciling: \(error.logIdentifier, privacy: .public) \(error.localizedDescription, privacy: .private)")
                needsReconciliation = true
            }
        }

        // Process insertions
        // The data is ALREADY in Core Data (we're fetching from it!)
        // We only need to update in-memory models, NOT save back to database
        for insertedId in batch.insertedIds {
            // An item this device is deleting right now is not added again: the notification
            // was queued before its row went. See CODE_AUDIT_21 §5.31.
            guard !itemControllable.itemDataModel.deletingIds.contains(insertedId) else { continue }
            do {
                guard let model = try await dataControllable.fetch(id: insertedId) else { continue }
                guard !itemControllable.itemDataModel.deletingIds.contains(insertedId) else { continue }
                // An "inserted" record can carry an id that is already loaded (the same package
                // imported on two devices): merge it like an update instead of replacing the
                // live instance and listing the id twice. See CODE_AUDIT_Folder §3.10.
                if itemControllable.itemSync(for: insertedId, noGame: true) != nil {
                    await itemControllable.mergeUpdates(model: model)
                } else {
                    itemControllable.resetModel(with: model)
                }
            } catch {
                Logger.syncDataControllable.error("updateFromSync insert \(insertedId, privacy: .public) failed: \(error.logIdentifier, privacy: .public) \(error.localizedDescription, privacy: .private)")
                needsReconciliation = true
            }
        }

        // Process updates
        for updatedId in batch.updatedIds {
            do {
                guard let model = try await dataControllable.fetch(id: updatedId),
                      !itemControllable.itemDataModel.deletingIds.contains(updatedId) else { continue }
                // Use mergeUpdates to avoid database writes during sync
                await itemControllable.mergeUpdates(model: model)
            } catch {
                Logger.syncDataControllable.error("updateFromSync update \(updatedId, privacy: .public) failed: \(error.logIdentifier, privacy: .public) \(error.localizedDescription, privacy: .private)")
                needsReconciliation = true
            }
        }

        if needsReconciliation {
            await fetchUpdates(from: dataControllable)
        }
        // A merged batch changes items without a save. See CODE_AUDIT_AppIntents §7.1.
        AppIntentContentInvalidator.invalidate()
    }

    private func fetchUpdates() async {
        await fetchUpdates(from: dataControllable)
    }

    private func fetchUpdates(from dataControllable: any DataPersistenceControllable) async {
        do {
            // Read before the fetch as well; see `updates(_:unsavedBeforeFetch:)`.
            let unsavedBeforeFetch = await dataControllable.unsavedInsertIds()
            let newItems = try await dataControllable.fetchAll()
            await itemControllable.updates(newItems, unsavedBeforeFetch: unsavedBeforeFetch)
        } catch {
            // Mirrors `updateFromSync`'s logging above — this full-table reconciliation
            // only runs once, at `start()`, so a failure here otherwise leaves no trace
            // of why items never loaded at launch. See CODE_AUDIT_EditItem §5.9.
            Logger.syncDataControllable.error("fetchUpdates() failed: \(error.logIdentifier, privacy: .public) \(error.localizedDescription, privacy: .private)")
        }
    }
}
