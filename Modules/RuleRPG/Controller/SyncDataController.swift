// @copyright André Trettin

import CoreData
import CoreRPG

struct SyncDataController: Sendable {
    @MainActor
    init(
        context: NSManagedObjectContext,
        dataControllable: any DataPersistenceControllable,
        itemController: ItemController
    ) {
        self.dataControllable = dataControllable
        itemControllable = itemController
        changeObserver = CoreDataChangeObserver()
        startSyncObservation(context: context, entity: RPGRule.entity())
    }

    let dataControllable: any DataPersistenceControllable
    let itemControllable: any ItemControllable
    let changeObserver: CoreDataChangeObserver
}

extension SyncDataController: SyncDataControllable {}

