// @copyright André Trettin

import CoreRPG
import CoreData
import CoreSpotlight

extension RPGPdf: CoreDataId {}
extension RPGPdfEntry: CoreDataId {}

extension RPGPdf {
    var entriesModel: [RPGPdfEntry] {
        get { RPGPdfEntry.sortedArray(from: entries) }
        set { entries = NSSet(array: newValue) }
    }
}

extension RPGPdf: SpotlightIndexerAttribute {
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
        attributeSet.relate(to: PdfEntity.self, itemId: uuid)
        return attributeSet
    }
#endif
}

extension RPGPdfEntry: SpotlightIndexerAttribute {
#if !os(tvOS)
    public func attributeSet() -> CSSearchableItemAttributeSet {
        let attributeSet = CSSearchableItemAttributeSet(contentType: .text)
        attributeSet.identifier = (uuid ?? UUID()).uuidString
        attributeSet.displayName = CRDT(wrappedValue: name ?? "").wrappedValue
        attributeSet.title = CRDT(wrappedValue: name ?? "").wrappedValue
        attributeSet.textContent = CRDT(wrappedValue: content ?? "").wrappedValue
        attributeSet.relate(to: PdfEntity.self, itemId: pdf?.uuid)
        return attributeSet
    }
#endif
}
