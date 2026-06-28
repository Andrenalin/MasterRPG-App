// @copyright André Trettin

import Foundation
import CoreData
import Observation

public protocol SyncDataControllable: Sendable {
    var dataControllable: any CoreDataPersistable { get }
    var itemControllable: any ItemControllable { get }
    var editControllable: any EditControllable { get }
}

// MARK: Core Data --> CloudKit Sync

public extension SyncDataControllable {
    func start() {
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
                    file: "ItemSyncable.swift"
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
                // Sync errors are non-fatal; the next CloudKit notification will retry
            }
        }
    }
    
    private func fetchUpdates() async {
        guard let newItems = try? await dataControllable.fetch() else { return }
        await itemControllable.updates(newItems)
    }
}
