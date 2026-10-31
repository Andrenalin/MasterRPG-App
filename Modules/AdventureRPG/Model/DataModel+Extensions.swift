// @copyright André Trettin

import CoreRPG
import CoreData
import CoreSpotlight

extension RPGAdventure: CoreDataId {}
extension RPGAdventureEntry: CoreDataId {}

extension RPGAdventure {
    var entriesModel: [RPGAdventureEntry] {
        get { RPGAdventureEntry.sortedArray(from: entries) }
        set { entries = NSSet(array: newValue) }
    }
}

extension RPGAdventure: SpotlightIndexerAttribute {
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

extension RPGAdventureEntry: SpotlightIndexerAttribute {
#if !os(tvOS)
    public func attributeSet() -> CSSearchableItemAttributeSet {
        let attributeSet = CSSearchableItemAttributeSet(contentType: .text)
        attributeSet.identifier = (uuid ?? UUID()).uuidString
        attributeSet.displayName = CRDT(wrappedValue: name ?? "").wrappedValue
        attributeSet.title = CRDT(wrappedValue: name ?? "").wrappedValue
        attributeSet.textContent = CRDT(wrappedValue: content ?? "").wrappedValue
        attributeSet.relate(to: AdventureEntity.self, itemId: adventure?.uuid)
        return attributeSet
    }
#endif
}
