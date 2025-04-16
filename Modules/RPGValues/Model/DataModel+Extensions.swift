// @copyright André Trettin

import AndrenalinKit
import CoreData
import CoreSpotlight

extension RPGValue: CoreDataId {}
extension RPGValueEntry: CoreDataId {}

extension RPGValue {
    var entriesModel: [RPGValueEntry] {
        get {
            guard let all = entries?.allObjects as? [RPGValueEntry] else {
                return []
            }
            return all.sorted { $0.index < $1.index }
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
            guard let all = photos?.allObjects as? [RPGValuePhoto] else {
                return []
            }
            return all.sorted { $0.index < $1.index }
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
}

extension RPGValueEntry: SpotlightIndexerAtyribute {
    public func attributeSet() -> CSSearchableItemAttributeSet {
        let attributeSet = CSSearchableItemAttributeSet(contentType: .text)
        attributeSet.identifier = (uuid ?? UUID()).uuidString
        attributeSet.displayName = CRDT(wrappedValue: name ?? "").wrappedValue
        attributeSet.title = CRDT(wrappedValue: name ?? "").wrappedValue
        attributeSet.textContent = CRDT(wrappedValue: value ?? "").wrappedValue
        return attributeSet
    }
}
