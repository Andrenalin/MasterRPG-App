//// @copyright André Trettin
//
//import Foundation
//import SwiftData
//
//@Model
//public final class RPGMapEntry {
//    init(uuid: UUID = UUID(), name: String = "", content: String = "", index: Int16 = 0, coordinatesUpdate: String = "", isHexGrid: Bool = false, isShown: Bool = false, coordinates: [RPGPosition]? = nil, map: RPGMap? = nil) {
//        self.uuid = uuid
//        self.name = name
//        self.content = content
//        self.index = index
//        self.coordinatesUpdate = coordinatesUpdate
//        self.isHexGrid = isHexGrid
//        self.isShown = isShown
//        self.coordinates = coordinates
//        self.map = map
//    }
//    
//    var uuid: UUID?
//    var name: String = ""
//    var content: String = ""
//
//    var index: Int16 = 0
//
//    var coordinatesUpdate: String = ""
//    var isHexGrid: Bool = false
//    var isShown: Bool = false
//
//    @Relationship(deleteRule: .cascade) var coordinates: [RPGPosition]?
//    var map: RPGMap?
//}
