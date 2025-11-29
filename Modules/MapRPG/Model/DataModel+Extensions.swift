// @copyright André Trettin

import CoreRPG
import CoreData
import CoreSpotlight

extension RPGMap: CoreDataId {}
extension RPGMapEntry: CoreDataId {}
extension RPGDisplayConfig: CoreDataId {}
extension RPGMapPin: CoreDataId {}

extension RPGMap {
    var entryModels: [RPGMapEntry] {
        get {
            guard let all = entries?.allObjects as? [RPGMapEntry] else {
                return []
            }
            return all.sorted { $0.index < $1.index }
        }
        set {
            entries = NSSet(array: newValue)
        }
    }
    
    func entryOrNew(for uuid: UUID) -> RPGMapEntry {
        if let entry = entryModels.first(where: { $0.uuid == uuid }) {
            return entry
        }
        if let context = managedObjectContext {
            return RPGMapEntry(context: context)
        }
        fatalError("ManagedObjectContext should be available!")
    }
    
    var mapPinModels: [RPGMapPin] {
        get {
            guard let all = mapPins?.allObjects as? [RPGMapPin] else {
                return []
            }
            return all.sorted { $0.index < $1.index }
        }
        set {
            mapPins = NSSet(array: newValue)
        }
    }
    
    func mapPinOrNew(for uuid: UUID) -> RPGMapPin {
        if let mapPin = mapPinModels.first(where: { $0.uuid == uuid }) {
            return mapPin
        }
        if let context = managedObjectContext {
            return RPGMapPin(context: context)
        }
        fatalError("ManagedObjectContext should be available!")
    }
    
    func displyConfigOrNew(for _: UUID) -> RPGDisplayConfig {
        if let displayConfig {
            return displayConfig
        }
        if let context = managedObjectContext {
            return RPGDisplayConfig(context: context)
        }
        fatalError("ManagedObjectContext should be available!")
    }
}

extension RPGMapEntry {
    var coordinateModels: [RPGPosition] {
        get {
            guard let all = coordinates?.allObjects as? [RPGPosition] else {
                return []
            }
            return all.sorted { $0.index < $1.index }
        }
        set {
            coordinates = NSSet(array: newValue)
        }
    }
    
    func coordinateOrNew(for uuid: UUID) -> RPGPosition {
        if let coordinate = coordinateModels.first(where: { $0.uuid == uuid }) {
            return coordinate
        }
        if let context = managedObjectContext {
            return RPGPosition(context: context)
        }
        fatalError("ManagedObjectContext should be available!")
    }
}

extension RPGDisplayConfig {
    var tileCoordinateModels: [RPGPosition] {
        get {
            guard let all = tileCoordinates?.allObjects as? [RPGPosition] else {
                return []
            }
            return all.sorted { $0.index < $1.index }
        }
        set {
            tileCoordinates = NSSet(array: newValue)
        }
    }
    
    func coordinateOrNew(for uuid: UUID) -> RPGPosition {
        if let coordinate = tileCoordinateModels.first(where: { $0.uuid == uuid }) {
            return coordinate
        }
        if let context = managedObjectContext {
            return RPGPosition(context: context)
        }
        fatalError("ManagedObjectContext should be available!")
    }
}

extension RPGMapPin {
    func coordinateOrNew(for _: UUID) -> RPGPosition {
        if let coordinate = location {
            return coordinate
        }
        if let context = managedObjectContext {
            return RPGPosition(context: context)
        }
        fatalError("ManagedObjectContext should be available!")
    }
}

extension RPGMap: SpotlightIndexerAtyribute {
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

extension RPGMapEntry: SpotlightIndexerAtyribute {
#if !os(tvOS)
    public func attributeSet() -> CSSearchableItemAttributeSet {
        let attributeSet = CSSearchableItemAttributeSet(contentType: .text)
        attributeSet.identifier = (uuid ?? UUID()).uuidString
        attributeSet.displayName = CRDT(wrappedValue: name ?? "").wrappedValue
        attributeSet.title = CRDT(wrappedValue: name ?? "").wrappedValue
        attributeSet.textContent = CRDT(wrappedValue: content ?? "").wrappedValue
        return attributeSet
    }
#endif
}
