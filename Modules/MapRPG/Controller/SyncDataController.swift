// @copyright André Trettin

import CoreRPG
import CoreData
import Foundation

struct SyncDataController: Sendable {
    @MainActor init(context: NSManagedObjectContext, dataControllable: any DataPersistenceControllable, itemController: ItemController) {
        self.dataControllable = dataControllable
        self.itemControllable = itemController
        self.changeObserver = CoreDataChangeObserver()

        changeObserver.observeCoreDataChanges(from: context, entity: RPGMap.entity(), handler: updateFromSync(deletedIds:insertedIds:updatedIds:))
    }

    let dataControllable: any DataPersistenceControllable
    let itemControllable: any ItemControllable
    let changeObserver: CoreDataChangeObserver
}

extension SyncDataController: SyncDataControllable {}
