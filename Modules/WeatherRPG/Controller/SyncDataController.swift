// @copyright André Trettin

import CoreRPG
import Foundation
import CoreData

struct SyncDataController: Sendable {
    @MainActor init(context: NSManagedObjectContext, dataControllable: any DataPersistenceControllable, itemController: ItemController) {
        self.dataControllable = dataControllable
        self.itemControllable = itemController
        self.changeObserver = CoreDataChangeObserver()
        startSyncObservation(context: context, entity: RPGWeather.entity())
    }

    let dataControllable: any DataPersistenceControllable
    let itemControllable: any ItemControllable
    let changeObserver: CoreDataChangeObserver
}

extension SyncDataController: SyncDataControllable {}
