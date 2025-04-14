// @copyright André Trettin

import AndrenalinKit
import CoreData

extension RPGPdf: CoreDataId {}
extension RPGPdfEntry: CoreDataId {}

extension RPGPdf {
    var entriesModel: [RPGPdfEntry] {
        get {
            guard let all = entries?.allObjects as? [RPGPdfEntry] else {
                return []
            }
            return all.sorted { $0.index < $1.index }
        }
        set {
            entries = NSSet(array: newValue)
        }
    }

    func entryOrNew(for uuid: UUID) -> RPGPdfEntry {
        if let entry = entriesModel.first(where: { $0.uuid == uuid }) {
            return entry
        }
        if let context = managedObjectContext {
            return RPGPdfEntry(context: context)
        }
        fatalError("ManagedObjectContext should be available!")
    }
}
