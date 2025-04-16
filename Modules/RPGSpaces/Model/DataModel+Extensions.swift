// @copyright André Trettin

import AndrenalinKit
import CoreData
import CoreSpotlight

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

extension RPGSpace: SpotlightIndexerAtyribute {
    public func attributeSet() -> CSSearchableItemAttributeSet {
        let attributeSet = CSSearchableItemAttributeSet(contentType: .text)
        attributeSet.identifier = (uuid ?? UUID()).uuidString
        attributeSet.displayName = CRDT(wrappedValue: name ?? "").wrappedValue
        attributeSet.title = CRDT(wrappedValue: name ?? "").wrappedValue
        attributeSet.textContent = CRDT(wrappedValue: information ?? "").wrappedValue
        let convertedTags = CRDT(string: tags ?? "", defaultValue: "")
        convertedTags.wrappedValue.split(separator: ",").forEach {
            if attributeSet.keywords != nil {
                attributeSet.keywords?.append(String($0))
            } else {
                attributeSet.keywords = [String($0)]
            }
        }
        return attributeSet
    }
}
