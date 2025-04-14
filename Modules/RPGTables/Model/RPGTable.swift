//// @copyright André Trettin
//
//import AndrenalinKit
//import Foundation
//import SwiftData
//
//@Model
//public final class RPGTable: SwiftDataType {
//    init(uuid: UUID = UUID(), name: String = "", information: String = "", tableCategory: String = "", tags: String = "", displayState: Int32 = 0, diceUUID: String = "", entriesUpdate: String = "", tableType: String = "", entries: [RPGTableEntry]? = nil) {
//        self.uuid = uuid
//        self.name = name
//        self.information = information
//        self.tableCategory = tableCategory
//        self.tags = tags
//        self.displayState = displayState
//        self.diceUUID = diceUUID
//        self.entriesUpdate = entriesUpdate
//        self.tableType = tableType
//        self.entries = entries
//    }
//    
//    public var uuid: UUID?
//    var name: String = ""
//    var information: String = ""
//    var tableCategory: String = ""
//    var tags: String = ""
//    var displayState: Int32 = 0
//
//    var diceUUID: String = ""
//    var entriesUpdate: String = ""
//    var tableType: String = ""
//
//    @Relationship(deleteRule: .cascade) var entries: [RPGTableEntry]?
//}

// @copyright André Trettin

//import AndrenalinKit
//import Foundation
//
//extension RPGTable {
//    var entriesModel: [RPGTableEntry] {
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
//    func entryOrNew(for uuid: UUID) -> RPGTableEntry {
//        if let entry = entriesModel.first(where: { $0.uuid == uuid }) {
//            return entry
//        }
//        return RPGTableEntry(uuid: uuid)
//    }
//}
