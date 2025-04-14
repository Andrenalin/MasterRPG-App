// @copyright André Trettin

import AndrenalinKit
import CoreData

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
