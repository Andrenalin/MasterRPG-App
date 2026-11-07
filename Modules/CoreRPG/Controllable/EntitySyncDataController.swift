// @copyright André Trettin

import CoreData
import Foundation

/// The CloudKit change observation of one module: every module's sync controller differs only
/// by its Core Data entity. See CODE_AUDIT_Audio2 §9.11.
public struct EntitySyncDataController: SyncDataControllable {
    @MainActor
    public init(
        context: NSManagedObjectContext,
        dataControllable: any DataPersistenceControllable,
        itemController: any ItemControllable,
        entity: NSEntityDescription
    ) {
        self.dataControllable = dataControllable
        self.itemControllable = itemController
        self.changeObserver = CoreDataChangeObserver()
        startSyncObservation(context: context, entity: entity)
    }

    public let dataControllable: any DataPersistenceControllable
    public let itemControllable: any ItemControllable
    public let changeObserver: CoreDataChangeObserver
}
