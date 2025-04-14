//// @copyright André Trettin
//
//import Foundation
//import SwiftData
//
//@Model
//public final class RPGDisplayConfig {
//    init(uuid: UUID = UUID(), borderColor: String? = nil, borderThickness: Double = 0.0, color: String = "", map: RPGMap? = nil, tileCoordinates: [RPGPosition]? = nil) {
//        self.uuid = uuid
//        self.borderColor = borderColor
//        self.borderThickness = borderThickness
//        self.color = color
//        self.map = map
//        self.tileCoordinates = tileCoordinates
//    }
//    
//    var uuid: UUID?
//    var borderColor: String?
//    var borderThickness: Double = 0.0
//    var color: String = ""
//    @Relationship(inverse: \RPGMap.displayConfig) var map: RPGMap?
//    @Relationship(deleteRule: .cascade, inverse: \RPGPosition.displayConfig) var tileCoordinates: [RPGPosition]?
//}
