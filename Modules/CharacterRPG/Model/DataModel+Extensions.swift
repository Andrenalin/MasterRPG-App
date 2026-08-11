// @copyright André Trettin

import CoreRPG
import CoreData
import CoreSpotlight

extension RPGValue: CoreDataId {}
extension RPGValueEntry: CoreDataId {}

extension RPGValue {
    var entriesModel: [RPGValueEntry] {
        get {
            guard let entries = entries as? Set<RPGValueEntry> else {
                return []
            }
            // Use NSSortDescriptor for efficient database-level sorting
            let sortDescriptor = NSSortDescriptor(key: "index", ascending: true)
            return (entries as NSSet).sortedArray(using: [sortDescriptor]).compactMap { $0 as? RPGValueEntry }
        }
        set {
            entries = NSSet(array: newValue)
        }
    }
    
    func entryOrNew(for uuid: UUID) -> RPGValueEntry {
        if let entry = entriesModel.first(where: { $0.uuid == uuid }) {
            return entry
        }
        guard let managedObjectContext else {
            preconditionFailure("RPGValue must belong to a managed object context before adding entries.")
        }
        return RPGValueEntry(context: managedObjectContext)
    }
    
    // MARK: Photos
    
    var photoIds: [RPGValuePhoto] {
        get {
            guard let photos = photos as? Set<RPGValuePhoto> else {
                return []
            }
            // Use NSSortDescriptor for efficient database-level sorting
            let sortDescriptor = NSSortDescriptor(key: "index", ascending: true)
            return (photos as NSSet).sortedArray(using: [sortDescriptor]).compactMap { $0 as? RPGValuePhoto }
        }
        set {
            photos = NSSet(array: newValue)
        }
    }
    
    func photoOrNew(for id: UUID) -> RPGValuePhoto {
        if let photo = photoIds.first(where: { $0.uuid == id }) {
            return photo
        }
        guard let managedObjectContext else {
            preconditionFailure("RPGValue must belong to a managed object context before adding a photo.")
        }
        return RPGValuePhoto(context: managedObjectContext)
    }
}

extension RPGValue: SpotlightIndexerAtyribute {
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

extension RPGValueEntry: SpotlightIndexerAtyribute {
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
