// @copyright André Trettin

import AndrenalinKit
import CoreData

extension RPGAdventure: CoreDataId {}
extension RPGAdventureEntry: CoreDataId {}

extension RPGAdventure {
    var entriesModel: [RPGAdventureEntry] {
        get {
            guard let all = entries?.allObjects as? [RPGAdventureEntry] else {
                return []
            }
            return all.sorted { $0.index < $1.index }
        }
        set {
            entries = NSSet(array: newValue)
        }
    }

    func entryOrNew(for uuid: UUID) -> RPGAdventureEntry {
        if let entry = entriesModel.first(where: { $0.uuid == uuid }) {
            return entry
        }
        if let context = managedObjectContext {
            return RPGAdventureEntry(context: context)
        }
        fatalError("ManagedObjectContext should be available!")
    }
}
