// @copyright André Trettin

import CoreRPG
import CoreData
import CoreSpotlight

extension RPGPhoto: CoreDataId {}
extension RPGPhotoEntry: CoreDataId {}

extension RPGPhoto {
    var entriesModel: [RPGPhotoEntry] {
        get { RPGPhotoEntry.sortedArray(from: entries) }
        set { entries = NSSet(array: newValue) }
    }

    func entryOrNew(for uuid: UUID) -> RPGPhotoEntry {
        childOrNew(uuid, in: entriesModel)
    }
}


extension RPGPhoto: SpotlightIndexerAttribute {
#if !os(tvOS)
    public func attributeSet() -> CSSearchableItemAttributeSet {
        let attributeSet = CSSearchableItemAttributeSet(contentType: .image)
        attributeSet.identifier = (uuid ?? UUID()).uuidString
        attributeSet.displayName = CRDT(wrappedValue: name ?? "").wrappedValue
        attributeSet.title = CRDT(wrappedValue: name ?? "").wrappedValue
        attributeSet.textContent = CRDT(wrappedValue: information ?? "").wrappedValue
        //attributeSet.thumbnailData =
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
