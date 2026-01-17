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
        Task.detached(priority: .userInitiated) {
            await fetchUpdates()
        }
    }
    
    @Sendable
    func updateFromSync(deletedIds: [UUID], insertedIds: [UUID], updatedIds: [UUID]) {
        Task.detached(priority: .userInitiated) {
            if !deletedIds.isEmpty {
                let ids = try await dataControllable.fetchIds()
                let removedIds = await Set(itemControllable.itemDataModel.items).subtracting(ids)
                for removedId in removedIds {
                    await itemControllable.delete(itemId: removedId)
                }
            }
            for insertedId in insertedIds {
                guard let model = try await dataControllable.fetch(id: insertedId) else { continue }
                await editControllable.save(updated: model)
            }
            for updatedId in updatedIds {
                guard let model = try await dataControllable.fetch(id: updatedId) else { continue }
                await editControllable.save(updated: model)
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
