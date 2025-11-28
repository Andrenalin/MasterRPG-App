// @copyright André Trettin

import AndrenalinKit
import CoreData
import Foundation

struct SyncDataController: Sendable {
    @MainActor init(context: NSManagedObjectContext, dataController: DataController, itemController: ItemController) {
        self.dataControllable = dataController
        self.itemControllable = itemController
        self.changeObserver = CoreDataChangeObserver()

        changeObserver.observeCoreDataChanges(from: context, entity: RPGMap.entity(), handler: updateFromSync(deletedIds:insertedIds:updatedIds:))
    }
    
    let dataControllable: any CoreDataPersistable
    let itemControllable: any ItemControllable
    let changeObserver: CoreDataChangeObserver
}

extension SyncDataController: SyncDataControllable {}
