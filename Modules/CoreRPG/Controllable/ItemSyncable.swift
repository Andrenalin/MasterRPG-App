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
            await CloudKitOperationCounter.shared.recordOperation(
                function: "SyncDataControllable.updateFromSync(deleted:\(deletedIds.count) inserted:\(insertedIds.count) updated:\(updatedIds.count))",
                file: "ItemSyncable.swift"
            )
            
            if !deletedIds.isEmpty {
                let ids = try await dataControllable.fetchIds()
                let removedIds = await Set(itemControllable.itemDataModel.items).subtracting(ids)
                for removedId in removedIds {
                    await itemControllable.delete(itemId: removedId, withFileData: false, withDatabase: false)
                }
            }
            
            // For inserted and updated items from sync:
            // The data is ALREADY in Core Data (we're fetching from it!)
            // We only need to update in-memory models, NOT save back to database
            for insertedId in insertedIds {
                guard let model = try await dataControllable.fetch(id: insertedId) else { continue }
                await itemControllable.resetModel(with: model)
            }
            for updatedId in updatedIds {
                guard let model = try await dataControllable.fetch(id: updatedId) else { continue }
                // Use replace with forceSave=false to skip database write
                await itemControllable.mergeUpdates(model: model)
            }
        }
    }
    
    private func fetchUpdates() async {
        guard let newItems = try? await dataControllable.fetch() else { return }
        //Task { @MainActor in
            await itemControllable.updates(newItems)
        //}
    }
}
