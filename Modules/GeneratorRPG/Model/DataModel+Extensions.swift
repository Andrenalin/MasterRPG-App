// @copyright André Trettin

import CoreRPG
import CoreData
import CoreSpotlight

extension RPGGenerator: CoreDataId {}
extension RPGGeneratorEntry: CoreDataId {}

extension RPGGenerator {
    var entriesModel: [RPGGeneratorEntry] {
        get {
            guard let entries = entries as? Set<RPGGeneratorEntry> else {
                return []
            }
            // Use NSSortDescriptor for efficient database-level sorting
            let sortDescriptor = NSSortDescriptor(key: "index", ascending: true)
            return (entries as NSSet).sortedArray(using: [sortDescriptor]) as! [RPGGeneratorEntry]
        }
        set {
            entries = NSSet(array: newValue)
        }
    }
    
    func entryOrNew(for uuid: UUID) -> RPGGeneratorEntry {
        if let entry = entriesModel.first(where: { $0.uuid == uuid }) {
            return entry
        }
        guard let managedObjectContext else {
            preconditionFailure("RPGGenerator must belong to a managed object context before adding entries.")
        }
        return RPGGeneratorEntry(context: managedObjectContext)
    }
}

extension RPGGenerator: SpotlightIndexerAtyribute {
#if !os(tvOS)
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
#endif
}
