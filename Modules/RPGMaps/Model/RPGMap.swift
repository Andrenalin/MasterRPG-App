//// @copyright André Trettin
//
//import AndrenalinKit
//import Foundation
//import SwiftData
//
//@Model
//public final class RPGMap: SwiftDataType {
//    init(uuid: UUID = UUID(), name: String = "", information: String = "", mapCategory: String = "", tags: String = "", displayState: Int32 = 0, displayConfigUpdate: String = "", entriesUpdate: String? = nil, height: Double = 0.0, hexMapScale: String = "", mapPinsUpdate: String = "", mapUpdate: String = "", photoUUID: UUID? = nil, pinScale: Double = 1, width: Double = 0.0, displayConfig: RPGDisplayConfig? = nil, entries: [RPGMapEntry]? = nil, mapPins: [RPGMapPin]? = nil) {
//        self.uuid = uuid
//        self.name = name
//        self.information = information
//        self.mapCategory = mapCategory
//        self.tags = tags
//        self.displayState = displayState
//        self.displayConfigUpdate = displayConfigUpdate
//        self.entriesUpdate = entriesUpdate
//        self.height = height
//        self.hexMapScale = hexMapScale
//        self.mapPinsUpdate = mapPinsUpdate
//        self.mapUpdate = mapUpdate
//        self.photoUUID = photoUUID
//        self.pinScale = pinScale
//        self.width = width
//        self.displayConfig = displayConfig
//        self.entries = entries
//        self.mapPins = mapPins
//    }
//    
//    public var uuid: UUID?
//    var name: String = ""
//    var information: String = ""
//    var mapCategory: String = ""
//    var tags: String = ""
//    var displayState: Int32 = 0
//
//    var displayConfigUpdate: String = ""
//    var entriesUpdate: String?
//    var height: Double = 0.0
//    var hexMapScale: String = ""
//    var mapPinsUpdate: String = ""
//    var mapUpdate: String = ""
//    var photoUUID: UUID?
//    var pinScale: Double = 1
//    var width: Double = 0.0
//    
//    @Relationship(deleteRule: .cascade) var displayConfig: RPGDisplayConfig?
//    @Relationship(deleteRule: .cascade) var entries: [RPGMapEntry]?
//    @Relationship(inverse: \RPGMapPin.map) var mapPins: [RPGMapPin]?
//}

// @copyright André Trettin

//import AndrenalinKit
//import Foundation
//
//extension RPGMap {
//    var entryModels: [RPGMapEntry] {
//        get {
//            guard let all = entries else {
//                return []
//            }
//            return all.sorted { $0.index < $1.index }
//        }
//        set {
//            entries = newValue
//        }
//    }
//
//    func entryOrNew(for uuid: UUID) -> RPGMapEntry {
//        if let entry = entryModels.first(where: { $0.uuid == uuid }) {
//            return entry
//        }
//        return RPGMapEntry(uuid: uuid)
//    }
//
//    var mapPinModels: [RPGMapPin] {
//        get {
//            guard let all = mapPins else {
//                return []
//            }
//            return all.sorted { $0.index < $1.index }
//        }
//        set {
//            mapPins = newValue
//        }
//    }
//
//    func mapPinOrNew(for uuid: UUID) -> RPGMapPin {
//        if let mapPin = mapPinModels.first(where: { $0.uuid == uuid }) {
//            return mapPin
//        }
//        return RPGMapPin(uuid: uuid)
//    }
//
//    func displyConfigOrNew(for uuid: UUID) -> RPGDisplayConfig {
//        if let displayConfig {
//            return displayConfig
//        }
//        return RPGDisplayConfig(uuid: uuid)
//    }
//}
//
//extension RPGMapEntry {
//    var coordinateModels: [RPGPosition] {
//        get {
//            guard let all = coordinates else {
//                return []
//            }
//            return all.sorted { $0.index < $1.index }
//        }
//        set {
//            coordinates = newValue
//        }
//    }
//
//    func coordinateOrNew(for uuid: UUID) -> RPGPosition {
//        if let coordinate = coordinateModels.first(where: { $0.uuid == uuid }) {
//            return coordinate
//        }
//        return RPGPosition(uuid: uuid)
//    }
//}
//
//extension RPGDisplayConfig {
//    var tileCoordinateModels: [RPGPosition] {
//        get {
//            guard let all = tileCoordinates else {
//                return []
//            }
//            return all.sorted { $0.index < $1.index }
//        }
//        set {
//            tileCoordinates = newValue
//        }
//    }
//
//    func coordinateOrNew(for uuid: UUID) -> RPGPosition {
//        if let coordinate = tileCoordinateModels.first(where: { $0.uuid == uuid }) {
//            return coordinate
//        }
//        return RPGPosition(uuid: uuid)
//    }
//}
//
//extension RPGMapPin {
//    func coordinateOrNew(for uuid: UUID) -> RPGPosition {
//        if let coordinate = location {
//            return coordinate
//        }
//        return RPGPosition(uuid: uuid)
//    }
//}
