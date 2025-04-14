// @copyright André Trettin

import AndrenalinKit
import CoreData

extension RPGAudio: CoreDataId {}
extension RPGAudioEntry: CoreDataId {}

extension RPGAudio {
    var entriesModel: [RPGAudioEntry] {
        get {
            guard let all = entries?.allObjects as? [RPGAudioEntry] else {
                return []
            }
            return all.sorted { $0.index < $1.index }
        }
        set {
            entries = NSSet(array: newValue)
        }
    }

    func entryOrNew(for uuid: UUID) -> RPGAudioEntry {
        if let entry = entriesModel.first(where: { $0.uuid == uuid }) {
            return entry
        }
        if let context = managedObjectContext {
            return RPGAudioEntry(context: context)
        }
        fatalError("ManagedObjectContext should be available!")
    }
}
