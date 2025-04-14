// @copyright André Trettin

import AndrenalinKit
import CoreData

extension RPGSpace: CoreDataId {}
extension RPGSpaceEntry: CoreDataId {}

extension RPGSpace {
    var entriesModel: [RPGSpaceEntry] {
        get {
            guard let all = entries?.allObjects as? [RPGSpaceEntry] else {
                return []
            }
            return all.sorted { $0.index < $1.index }
        }
        set {
            entries = NSSet(array: newValue)
        }
    }

    func entryOrNew(for uuid: UUID) -> RPGSpaceEntry {
        if let entry = entriesModel.first(where: { $0.uuid == uuid }) {
            return entry
        }
        if let context = managedObjectContext {
            return RPGSpaceEntry(context: context)
        }
        fatalError("ManagedObjectContext should be available!")
    }
}
