// @copyright André Trettin

import AndrenalinKit
import Foundation
import CoreData

struct SyncDataController: Sendable {
    @MainActor init(context: NSManagedObjectContext, dataController: DataController, itemController: ItemController) {
        self.dataControllable = dataController
        self.itemControllable = itemController
        self.changeObserver = CoreDataChangeObserver()

        changeObserver.observeCoreDataChanges(from: context, entity: RPGDice.entity(), handler: updateFromSync(deletedIds:insertedIds:updatedIds:))
    }
    
    let dataControllable: any CoreDataPersistable
    let itemControllable: any ItemControllable
    let changeObserver: CoreDataChangeObserver
}

extension SyncDataController: SyncDataControllable {}
