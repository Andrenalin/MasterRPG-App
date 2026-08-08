// @copyright André Trettin

import Foundation
import CoreData
import Observation
import os.log

public protocol SyncDataControllable: Sendable {
    var dataControllable: any DataPersistenceControllable { get }
    var itemControllable: any ItemControllable { get }
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

                // Process deletions
                if !deletedIds.isEmpty {
                    let ids = try await dataControllable.fetchIds()

                    // Safely access MainActor-isolated itemDataModel.items
                    let currentItems = await MainActor.run {
                        Set(itemControllable.itemDataModel.items)
                    }

                    let removedIds = currentItems.subtracting(ids)
                    for removedId in removedIds {
                        await itemControllable.delete(itemId: removedId, withFileData: false, withDatabase: false)
                    }
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
