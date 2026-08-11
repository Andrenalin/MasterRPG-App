// @copyright André Trettin

import CoreRPG
import CoreData
import CoreSpotlight

extension RPGDice: CoreDataId {}
extension RPGDiceEntry: CoreDataId {}

extension RPGDice {
    var entriesModel: [RPGDiceEntry] {
        get {
            guard let entries = entries as? Set<RPGDiceEntry> else {
                return []
            }
            // Use NSSortDescriptor for efficient database-level sorting
            let sortDescriptor = NSSortDescriptor(key: "index", ascending: true)
            return (entries as NSSet).sortedArray(using: [sortDescriptor]).compactMap { $0 as? RPGDiceEntry }
        }
        set {
            entries = NSSet(array: newValue)
        }
    }
    
    func entryOrNew(for uuid: UUID) -> RPGDiceEntry {
        if let entry = entriesModel.first(where: { $0.uuid == uuid }) {
            return entry
        }
        guard let managedObjectContext else {
            preconditionFailure("RPGDice must belong to a managed object context before adding entries.")
        }
        return RPGDiceEntry(context: managedObjectContext)
    }
}

extension RPGDice: SpotlightIndexerAtyribute {
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
