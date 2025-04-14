//// @copyright André Trettin
//
//import AndrenalinKit
//import Foundation
//import SwiftData
//
//
//@Model
//final public class RPGAudio: SwiftDataType {
//    internal init(uuid: UUID = UUID(), name: String = "", information: String = "", audioCategory: String = "", tags: String = "", displayState: Int32 = 0, entriesUpdate: String = "", fileUrl: String = "", fileUrlUpdate: String = "", entries: [RPGAudioEntry]? = nil) {
//        self.uuid = uuid
//        self.name = name
//        self.information = information
//        self.audioCategory = audioCategory
//        self.tags = tags
//        self.displayState = displayState
//        self.entriesUpdate = entriesUpdate
//        self.fileUrl = fileUrl
//        self.fileUrlUpdate = fileUrlUpdate
//        self.entries = entries
//    }
//    
//    public var uuid: UUID?
//    var name: String = ""
//    var information: String = ""
//    var audioCategory: String = ""
//    var tags: String = ""
//    var displayState: Int32 = 0
//
//    var entriesUpdate: String = ""
//    var fileUrl: String = ""
//    var fileUrlUpdate: String = ""
//    
//    @Relationship(deleteRule: .cascade, inverse: \RPGAudioEntry.audio) var entries: [RPGAudioEntry]?
//}

// @copyright André Trettin

//import AndrenalinKit
//import Foundation
//
//extension RPGAudio {
//    var entriesModel: [RPGAudioEntry] {
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
//    func entryOrNew(for uuid: UUID) -> RPGAudioEntry {
//        if let entry = entriesModel.first(where: { $0.uuid == uuid }) {
//            return entry
//        }
//        return RPGAudioEntry(uuid: uuid)
//    }
//}
