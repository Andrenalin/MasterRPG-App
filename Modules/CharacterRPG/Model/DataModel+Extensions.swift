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
            return (entries as NSSet).sortedArray(using: [sortDescriptor]) as! [RPGValueEntry]
        }
        set {
            entries = NSSet(array: newValue)
        }
    }
    
    func entryOrNew(for uuid: UUID) -> RPGValueEntry {
        if let entry = entriesModel.first(where: { $0.uuid == uuid }) {
            return entry
        }
        if let context = managedObjectContext {
            return RPGValueEntry(context: context)
        }
        fatalError("ManagedObjectContext should be available!")
    }
    
    // MARK: Photos
    
    var photoIds: [RPGValuePhoto] {
        get {
            guard let photos = photos as? Set<RPGValuePhoto> else {
                return []
            }
            // Use NSSortDescriptor for efficient database-level sorting
            let sortDescriptor = NSSortDescriptor(key: "index", ascending: true)
            return (photos as NSSet).sortedArray(using: [sortDescriptor]) as! [RPGValuePhoto]
        }
        set {
            photos = NSSet(array: newValue)
        }
    }
    
    func photoOrNew(for id: UUID) -> RPGValuePhoto {
        if let photo = photoIds.first(where: { $0.uuid == id }) {
            return photo
        }
        if let context = managedObjectContext {
            return RPGValuePhoto(context: context)
        }
        fatalError("ManagedObjectContext should be available!")
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
