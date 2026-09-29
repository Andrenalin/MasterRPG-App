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
        Task { @MainActor in
            // Chain onto (rather than cancel) any still-in-flight sync from a previous
            // notification, so overlapping CloudKit change batches for this module apply
            // in arrival order without ever discarding part of an in-flight batch. This
            // used to `cancel()` the previous task instead: since each loop below checked
            // cancellation per-item, a notification arriving mid-batch could cut off the
            // previous batch's remaining deletes, leaving those items permanently "deleted
            // in Core Data, still present in ItemDataModel" until the app relaunched — and
            // if the user then edited/saved one of those ghost items, `CoreDataController`
            // would silently recreate (and re-sync) the row it had already deleted. See
            // CODE_AUDIT §3.1. Awaiting the predecessor's `.value` preserves the original
            // ordering guarantee (mirrors the intent behind `FolderListControllable`'s own
            // cancel-and-replace pattern, see CODE_AUDIT_EditItem §3.2) without dropping work.
            let previousTask = itemControllable.itemDataModel.pendingSyncTask
            itemControllable.itemDataModel.pendingSyncTask = Task(priority: .userInitiated) {
                await previousTask?.value
                await CloudKitOperationCounter.shared.recordOperation(
                    function: "SyncDataControllable.updateFromSync(deleted:\(deletedIds.count) inserted:\(insertedIds.count) updated:\(updatedIds.count))",
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
                if !deletedIds.isEmpty {
                    do {
                        let currentIds = Set(try await dataControllable.fetchIds())
                        // An item created on this device whose insert is still queued is not in
                        // Core Data yet either: it must not be mistaken for a remote deletion,
                        // or deleting it would also drop its queued insert for good.
                        // See CODE_AUDIT_18 §5.2.
                        let unsavedInsertIds = await dataControllable.unsavedInsertIds()
                        let staleIds = itemControllable.itemDataModel.items.filter {
                            !currentIds.contains($0) && !unsavedInsertIds.contains($0)
                        }
                        for staleId in staleIds {
                            await itemControllable.delete(itemId: staleId, withFileData: false, withDatabase: false)
                        }
                    } catch {
                        Logger.syncDataControllable.error("updateFromSync deletion diff failed, reconciling: \(error.localizedDescription, privacy: .public)")
                        needsReconciliation = true
                    }
                }

                // Process insertions
                // The data is ALREADY in Core Data (we're fetching from it!)
                // We only need to update in-memory models, NOT save back to database
                for insertedId in insertedIds {
                    do {
                        guard let model = try await dataControllable.fetch(id: insertedId) else { continue }
                        // `resetModel(with:)` is itself `@MainActor` — `await` alone hops, same as
                        // `delete(itemId:...)` above; no `MainActor.run` wrapper needed.
                        itemControllable.resetModel(with: model)
                    } catch {
                        Logger.syncDataControllable.error("updateFromSync insert \(insertedId, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                        needsReconciliation = true
                    }
                }

                // Process updates
                for updatedId in updatedIds {
                    do {
                        guard let model = try await dataControllable.fetch(id: updatedId) else { continue }
                        // Use mergeUpdates to avoid database writes during sync
                        itemControllable.mergeUpdates(model: model)
                    } catch {
                        Logger.syncDataControllable.error("updateFromSync update \(updatedId, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                        needsReconciliation = true
                    }
                }

                if needsReconciliation {
                    await fetchUpdates()
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
