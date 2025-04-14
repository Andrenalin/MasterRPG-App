// @copyright André Trettin

import AndrenalinKit
import CoreData

extension RPGValue: CoreDataId {}
extension RPGValueEntry: CoreDataId {}

extension RPGValue {
    var entriesModel: [RPGValueEntry] {
        get {
            guard let all = entries?.allObjects as? [RPGValueEntry] else {
                return []
            }
            return all.sorted { $0.index < $1.index }
        }
        set {
            entries = NSSet(array: newValue)
        }
    }

    func entryOrNew(for uuid: UUID) -> RPGValueEntry {
        if let entry = entriesModel.first(where: { $0.uuid == uuid }) {
            return entry
        }
        if let context = managedObjectContext {
            return RPGValueEntry(context: context)
        }
        fatalError("ManagedObjectContext should be available!")
    }

    // MARK: Photos

    var photoIds: [RPGValuePhoto] {
        get {
            guard let all = photos?.allObjects as? [RPGValuePhoto] else {
                return []
            }
            return all.sorted { $0.index < $1.index }
        }
        set {
            photos = NSSet(array: newValue)
        }
    }

    func photoOrNew(for id: UUID) -> RPGValuePhoto {
        if let photo = photoIds.first(where: { $0.uuid == id }) {
            return photo
        }
        if let context = managedObjectContext {
            return RPGValuePhoto(context: context)
        }
        fatalError("ManagedObjectContext should be available!")
    }
}
