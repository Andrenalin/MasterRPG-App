//// @copyright André Trettin
//
//import AndrenalinKit
//import Foundation
//import SwiftData
//
//@Model
//public final class RPGPdf: SwiftDataType {
//    internal init(uuid: UUID = UUID(), displayState: Int32 = 0, entriesUpdate: String = "", fileUrl: String = "", fileUrlUpdate: String = "", information: String = "", name: String = "", pdfCategory: String = "", tags: String = "", entries: [RPGPdfEntry]? = nil) {
//        self.uuid = uuid
//        self.displayState = displayState
//        self.entriesUpdate = entriesUpdate
//        self.fileUrl = fileUrl
//        self.fileUrlUpdate = fileUrlUpdate
//        self.information = information
//        self.name = name
//        self.pdfCategory = pdfCategory
//        self.tags = tags
//        self.entries = entries
//    }
//    
//    public var uuid: UUID?
//    var name: String = ""
//    var information: String = ""
//    var pdfCategory: String = ""
//    var tags: String = ""
//    var displayState: Int32 = 0
//
//    var entriesUpdate: String = ""
//    var fileUrl: String = ""
//    var fileUrlUpdate: String = ""
//    
//    @Relationship(deleteRule: .cascade) var entries: [RPGPdfEntry]?
//}

// @copyright André Trettin

//import AndrenalinKit
//import Foundation
//
//extension RPGPdf {
//    var entriesModel: [RPGPdfEntry] {
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
//    func entryOrNew(for uuid: UUID) -> RPGPdfEntry {
//        if let entry = entriesModel.first(where: { $0.uuid == uuid }) {
//            return entry
//        }
//        return RPGPdfEntry(uuid: uuid)
//    }
//}
