// @copyright André Trettin

import AndrenalinKit
import CoreData

extension RPGTable: CoreDataId {}
extension RPGTableEntry: CoreDataId {}

extension RPGTable {
    var entriesModel: [RPGTableEntry] {
        get {
            guard let all = entries?.allObjects as? [RPGTableEntry] else {
                return []
            }
            return all.sorted { $0.index < $1.index }
        }
        set {
            entries = NSSet(array: newValue)
        }
    }

    func entryOrNew(for uuid: UUID) -> RPGTableEntry {
        if let entry = entriesModel.first(where: { $0.uuid == uuid }) {
            return entry
        }
        if let context = managedObjectContext {
            return RPGTableEntry(context: context)
        }
        fatalError("ManagedObjectContext should be available!")
    }
}
