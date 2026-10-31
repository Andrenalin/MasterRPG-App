// @copyright André Trettin

import CoreData
import CoreRPG
import CoreSpotlight

extension RPGRule: CoreDataId {}
extension RPGRuleEntry: CoreDataId {}

extension RPGRule {
    var entriesModel: [RPGRuleEntry] {
        get { RPGRuleEntry.sortedArray(from: entries) }
        set { entries = NSSet(array: newValue) }
    }

}

extension RPGRule: SpotlightIndexerAttribute {
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

extension RPGRuleEntry: SpotlightIndexerAttribute {
#if !os(tvOS)
    public func attributeSet() -> CSSearchableItemAttributeSet {
        let attributes = CSSearchableItemAttributeSet(contentType: .text)
        attributes.identifier = (uuid ?? UUID()).uuidString
        attributes.displayName = name ?? ""
        attributes.title = name ?? ""
        attributes.textContent = content ?? ""
        attributes.relate(to: RuleEntity.self, itemId: rule?.uuid)
        return attributes
    }
#endif
}

