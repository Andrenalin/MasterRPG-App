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
        changeObserver.observeCoreDataChanges(
            from: context,
            entity: RPGRule.entity(),
            handler: updateFromSync(deletedIds:insertedIds:updatedIds:)
        )
    }

    let dataControllable: any DataPersistenceControllable
    let itemControllable: any ItemControllable
    let changeObserver: CoreDataChangeObserver
}

extension SyncDataController: SyncDataControllable {}

