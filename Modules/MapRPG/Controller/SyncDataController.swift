// @copyright André Trettin

import CoreRPG
import CoreData
import Foundation

struct SyncDataController: Sendable {
    @MainActor init(context: NSManagedObjectContext, dataController: DataController, editController: EditController) {
        self.dataControllable = dataController
        self.editControllable = editController
        self.itemControllable = editController.itemControllable
        self.changeObserver = CoreDataChangeObserver()

        changeObserver.observeCoreDataChanges(from: context, entity: RPGMap.entity(), handler: updateFromSync(deletedIds:insertedIds:updatedIds:))
    }
    
    let dataControllable: any CoreDataPersistable
    let editControllable: any EditControllable
    let itemControllable: any ItemControllable
    let changeObserver: CoreDataChangeObserver
}

extension SyncDataController: SyncDataControllable {}
