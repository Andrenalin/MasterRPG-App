//// @copyright André Trettin
//
//import Foundation
//import SwiftData
//
//@Model
//public final class RPGPosition {
//    init(uuid: UUID = UUID(), index: Int16 = 0, xPos: Double = 0.0, yPos: Double = 0.0, displayConfig: RPGDisplayConfig? = nil, mapEntries: RPGMapEntry? = nil, mapPin: RPGMapPin? = nil) {
//        self.uuid = uuid
//        self.index = index
//        self.xPos = xPos
//        self.yPos = yPos
//        self.displayConfig = displayConfig
//        self.mapEntries = mapEntries
//        self.mapPin = mapPin
//    }
//    
//    var uuid: UUID?
//    var index: Int16 = 0
//    var xPos: Double = 0.0
//    var yPos: Double = 0.0
//    var displayConfig: RPGDisplayConfig?
//    var mapEntries: RPGMapEntry?
//    @Relationship(inverse: \RPGMapPin.location) var mapPin: RPGMapPin?
//}
