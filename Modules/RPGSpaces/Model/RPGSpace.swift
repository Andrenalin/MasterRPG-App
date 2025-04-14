//// @copyright André Trettin
//
//import AndrenalinKit
//import Foundation
//import SwiftData
//
//@Model
//public final class RPGSpace: SwiftDataType {
//    init(uuid: UUID = UUID(), name: String = "", information: String = "", spaceCategory: String = "", tags: String = "", displayState: Int32 = 0, degrees: String = "", entriesUpdate: String = "", fileUrl: String = "", fileUrlUpdate: String = "", entries: [RPGSpaceEntry]? = nil) {
//        self.uuid = uuid
//        self.name = name
//        self.information = information
//        self.spaceCategory = spaceCategory
//        self.tags = tags
//        self.displayState = displayState
//        self.degrees = degrees
//        self.entriesUpdate = entriesUpdate
//        self.fileUrl = fileUrl
//        self.fileUrlUpdate = fileUrlUpdate
//        self.entries = entries
//    }
//    
//    public var uuid: UUID?
//    var name: String = ""
//    var information: String = ""
//    var spaceCategory: String = ""
//    var tags: String = ""
//    var displayState: Int32 = 0
//
//    var degrees: String = ""
//    var entriesUpdate: String = ""
//    var fileUrl: String = ""
//    var fileUrlUpdate: String = ""
//    
//    @Relationship(deleteRule: .cascade) var entries: [RPGSpaceEntry]?
//}
//
//// @copyright André Trettin
//
//import AndrenalinKit
//import Foundation
//
//extension RPGSpace {
//    var entriesModel: [RPGSpaceEntry] {
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
//    func entryOrNew(for uuid: UUID) -> RPGSpaceEntry {
//        if let entry = entriesModel.first(where: { $0.uuid == uuid }) {
//            return entry
//        }
//        return RPGSpaceEntry(uuid: uuid)
//    }
//}
