// @copyright André Trettin

import CoreData
import CoreRPG
import CoreSpotlight

extension RPGRule: CoreDataId {}
extension RPGRuleEntry: CoreDataId {}

extension RPGRule {
    var entriesModel: [RPGRuleEntry] {
        get {
            let values = (entries as? Set<RPGRuleEntry>) ?? []
            return values.sorted { lhs, rhs in lhs.index < rhs.index }
        }
        set {
            entries = NSSet(array: newValue)
        }
    }

    func entryOrNew(for id: UUID) -> RPGRuleEntry {
        if let entry = entriesModel.first(where: { $0.uuid == id }) {
            return entry
        }
        guard let managedObjectContext else {
            preconditionFailure("RPGRule must belong to a managed object context before adding entries.")
        }
        return RPGRuleEntry(context: managedObjectContext)
    }
}

extension RPGRule: SpotlightIndexerAtyribute {
#if !os(tvOS)
    public func attributeSet() -> CSSearchableItemAttributeSet {
        let attributes = CSSearchableItemAttributeSet(contentType: .text)
        attributes.identifier = (uuid ?? UUID()).uuidString
        attributes.displayName = CRDT(wrappedValue: name ?? "").wrappedValue
        attributes.title = CRDT(wrappedValue: name ?? "").wrappedValue
        attributes.textContent = CRDT(wrappedValue: information ?? "").wrappedValue
        let convertedTags = CRDT(string: tags ?? "", defaultValue: [String]())
        attributes.keywords = convertedTags.wrappedValue
        return attributes
    }
#endif
}

extension RPGRuleEntry: SpotlightIndexerAtyribute {
#if !os(tvOS)
    public func attributeSet() -> CSSearchableItemAttributeSet {
        let attributes = CSSearchableItemAttributeSet(contentType: .text)
        attributes.identifier = (uuid ?? UUID()).uuidString
        attributes.displayName = name ?? ""
        attributes.title = name ?? ""
        attributes.textContent = content ?? ""
        return attributes
    }
#endif
}

