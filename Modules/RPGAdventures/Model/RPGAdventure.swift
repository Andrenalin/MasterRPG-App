// @copyright André Trettin
//
//import AndrenalinKit
//import Foundation
//import SwiftData
//
//@Model
//public final class RPGAdventure: SwiftDataType {
//    init(uuid: UUID = UUID(), name: String = "New", information: String = "", adventureCategory: String = "", tags: String = "", displayState: Int32 = 0, entriesUpdate: String = "", photoUUID: String? = nil, entries: [RPGAdventureEntry]? = nil) {
//        self.uuid = uuid
//        self.name = name
//        self.information = information
//        self.adventureCategory = adventureCategory
//        self.tags = tags
//        self.displayState = displayState
//        self.entriesUpdate = entriesUpdate
//        self.photoUUID = photoUUID
//        self.entries = entries
//    }
//    
//    public var uuid: UUID?
//    var name: String = "New"
//    var information: String = ""
//    var adventureCategory: String = ""
//    var tags: String = ""
//    var displayState: Int32 = 0
//
//    var entriesUpdate: String = ""
//    var photoUUID: String?
//    @Relationship(deleteRule: .cascade, inverse: \RPGAdventureEntry.adventure) var entries: [RPGAdventureEntry]?
//}

// @copyright André Trettin

//import AndrenalinKit
//import Foundation
//
//extension RPGAdventure {
//    var entriesModel: [RPGAdventureEntry] {
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
//    func entryOrNew(for uuid: UUID) -> RPGAdventureEntry {
//        if let entry = entriesModel.first(where: { $0.uuid == uuid }) {
//            return entry
//        }
//        return RPGAdventureEntry(uuid: uuid)
//    }
//}
