// @copyright André Trettin

import CoreRPG
import CoreData
import CoreSpotlight
import os.log

extension RPGMap: CoreDataId {}
extension RPGMapEntry: CoreDataId {}
extension RPGDisplayConfig: CoreDataId {}
extension RPGMapPin: CoreDataId {}

extension RPGMap {
    var entryModels: [RPGMapEntry] {
        get { RPGMapEntry.sortedArray(from: entries) }
        set { entries = NSSet(array: newValue) }
    }

    var mapPinModels: [RPGMapPin] {
        get { RPGMapPin.sortedArray(from: mapPins) }
        set { mapPins = NSSet(array: newValue) }
    }

    /// `nil` when this map has no `managedObjectContext` — it was deleted by a
    /// concurrent merge (e.g. a CloudKit sync from another device) in the
    /// window between being fetched and this running. The caller skips this
    /// sync step; the next sync pass reconciles it once the deletion (or a
    /// re-fetch) has settled, instead of crashing the process. See CODE_AUDIT §5.2.
    func displayConfigOrNew(for _: UUID) -> RPGDisplayConfig? {
        if let displayConfig {
            return displayConfig
        }
        guard let managedObjectContext else {
            Logger.syncDataControllable.error("RPGMap has no managedObjectContext while adding a display config — likely deleted by a concurrent merge. Skipping this sync step.")
            return nil
        }
        return RPGDisplayConfig(context: managedObjectContext)
    }
}

extension RPGMapEntry {
    var coordinateModels: [RPGPosition] {
        get { RPGPosition.sortedArray(from: coordinates) }
        set { coordinates = NSSet(array: newValue) }
    }

    /// See `RPGMap.displayConfigOrNew(for:)` — same concurrent-deletion race, same graceful bail-out.
    func newCoordinate() -> RPGPosition? {
        guard let managedObjectContext else {
            Logger.syncDataControllable.error("RPGMapEntry has no managedObjectContext while adding a coordinate — likely deleted by a concurrent merge. Skipping this sync step.")
            return nil
        }
        return RPGPosition(context: managedObjectContext)
    }
}

extension RPGDisplayConfig {
    var tileCoordinateModels: [RPGPosition] {
        get { RPGPosition.sortedArray(from: tileCoordinates) }
        set { tileCoordinates = NSSet(array: newValue) }
    }

    /// See `RPGMap.displayConfigOrNew(for:)` — same concurrent-deletion race, same graceful bail-out.
    func newCoordinate() -> RPGPosition? {
        guard let managedObjectContext else {
            Logger.syncDataControllable.error("RPGDisplayConfig has no managedObjectContext while adding a coordinate — likely deleted by a concurrent merge. Skipping this sync step.")
            return nil
        }
        return RPGPosition(context: managedObjectContext)
    }
}

extension RPGMapPin {
    /// See `RPGMap.displayConfigOrNew(for:)` — same concurrent-deletion race, same graceful bail-out.
    func coordinateOrNew(for _: UUID) -> RPGPosition? {
        if let coordinate = location {
            return coordinate
        }
        guard let managedObjectContext else {
            Logger.syncDataControllable.error("RPGMapPin has no managedObjectContext while adding a coordinate — likely deleted by a concurrent merge. Skipping this sync step.")
            return nil
        }
        return RPGPosition(context: managedObjectContext)
    }
}

extension RPGMap: SpotlightIndexerAttribute {
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
        attributeSet.relate(to: MapEntity.self, itemId: uuid)
        return attributeSet
    }
#endif
}

extension RPGMapEntry: SpotlightIndexerAttribute {
#if !os(tvOS)
    public func attributeSet() -> CSSearchableItemAttributeSet {
        let attributeSet = CSSearchableItemAttributeSet(contentType: .text)
        attributeSet.identifier = (uuid ?? UUID()).uuidString
        attributeSet.displayName = CRDT(wrappedValue: name ?? "").wrappedValue
        attributeSet.title = CRDT(wrappedValue: name ?? "").wrappedValue
        attributeSet.textContent = CRDT(wrappedValue: content ?? "").wrappedValue
        attributeSet.relate(to: MapEntity.self, itemId: map?.uuid)
        return attributeSet
    }
#endif
}
