// @copyright André Trettin

import CoreRPG
import CoreData
import CoreSpotlight

extension RPGValue: CoreDataId {}
extension RPGValueEntry: CoreDataId {}
extension RPGValuePhoto: CoreDataId {}

extension RPGValue {
    var entriesModel: [RPGValueEntry] {
        get { RPGValueEntry.sortedArray(from: entries) }
        set { entries = NSSet(array: newValue) }
    }

    func entryOrNew(for uuid: UUID) -> RPGValueEntry {
        childOrNew(uuid, in: entriesModel)
    }

    // MARK: Photos

    var photoIds: [RPGValuePhoto] {
        get { RPGValuePhoto.sortedArray(from: photos) }
        set { photos = NSSet(array: newValue) }
    }

    func photoOrNew(for id: UUID) -> RPGValuePhoto {
        childOrNew(id, in: photoIds)
    }
}

extension RPGValue: SpotlightIndexerAttribute {
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

extension RPGValueEntry: SpotlightIndexerAttribute {
#if !os(tvOS)
    public func attributeSet() -> CSSearchableItemAttributeSet {
        let attributeSet = CSSearchableItemAttributeSet(contentType: .text)
        attributeSet.identifier = (uuid ?? UUID()).uuidString
        attributeSet.displayName = CRDT(wrappedValue: name ?? "").wrappedValue
        attributeSet.title = CRDT(wrappedValue: name ?? "").wrappedValue
        attributeSet.textContent = CRDT(wrappedValue: value ?? "").wrappedValue
        return attributeSet
    }
#endif
}
