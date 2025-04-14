// @copyright André Trettin

import AndrenalinKit
import CoreData

extension RPGPhoto: CoreDataId {}
extension RPGPhotoEntry: CoreDataId {}

extension RPGPhoto {
    var entriesModel: [RPGPhotoEntry] {
        get {
            guard let all = entries?.allObjects as? [RPGPhotoEntry] else {
                return []
            }
            return all.sorted { $0.index < $1.index }
        }
        set {
            entries = NSSet(array: newValue)
        }
    }

    func entryOrNew(for uuid: UUID) -> RPGPhotoEntry {
        if let entry = entriesModel.first(where: { $0.uuid == uuid }) {
            return entry
        }
        if let context = managedObjectContext {
            return RPGPhotoEntry(context: context)
        }
        fatalError("ManagedObjectContext should be available!")
    }
}
