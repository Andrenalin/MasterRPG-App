//// @copyright André Trettin
//
//import Foundation
//import SwiftData
//
//@Model
//public final class RPGMapPin {
//    init(uuid: UUID = UUID(), name: String = "", index: Int16 = 0, color: String = "", isShown: Bool = true, photoUUID: UUID? = nil, size: Int16 = 0, location: RPGPosition? = nil, map: RPGMap? = nil) {
//        self.uuid = uuid
//        self.name = name
//        self.index = index
//        self.color = color
//        self.isShown = isShown
//        self.photoUUID = photoUUID
//        self.size = size
//        self.location = location
//        self.map = map
//    }
//    
//    var uuid: UUID?
//    var name: String = ""
//    var index: Int16 = 0
//
//    var color: String = ""
//    var isShown: Bool = true
//    var photoUUID: UUID?
//    var size: Int16 = 0
//    @Relationship(deleteRule: .cascade) var location: RPGPosition?
//    var map: RPGMap?
//}
