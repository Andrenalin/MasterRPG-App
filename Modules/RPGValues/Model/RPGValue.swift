//// @copyright André Trettin
//
//import AndrenalinKit
//import Foundation
//import SwiftData
//
//@Model
//public final class RPGValue: SwiftDataType {
//    internal init(uuid: UUID? = nil, name: String? = nil, information: String? = nil, valueCategory: String = "", tags: String? = nil, displayState: Int32 = 0, entriesUpdate: String = "", parentUUID: UUID? = nil, photosUpdate: String = "", photoUUID: String? = "", entries: [RPGValueEntry]? = nil, photos: [RPGValuePhoto]? = nil) {
//        self.uuid = uuid
//        self.name = name
//        self.information = information
//        self.valueCategory = valueCategory
//        self.tags = tags
//        self.displayState = displayState
//        self.entriesUpdate = entriesUpdate
//        self.parentUUID = parentUUID
//        self.photosUpdate = photosUpdate
//        self.photoUUID = photoUUID
//        self.entries = entries
//        self.photos = photos
//    }
//    
//    public var uuid: UUID?
//    var name: String?
//    var information: String?
//    var valueCategory: String = ""
//    var tags: String?
//    var displayState: Int32 = 0
//    
//    var entriesUpdate: String = ""
//    var parentUUID: UUID?
//    var photosUpdate: String = ""
//    var photoUUID: String? = ""
//    
//    @Relationship(deleteRule: .cascade) var entries: [RPGValueEntry]?
//    @Relationship(deleteRule: .cascade) var photos: [RPGValuePhoto]?
//}
//
//// @copyright André Trettin
//
//import AndrenalinKit
//import Foundation
//
//extension RPGValue {
//    var entriesModel: [RPGValueEntry] {
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
//    func entryOrNew(for uuid: UUID) -> RPGValueEntry {
//        if let entry = entriesModel.first(where: { $0.uuid == uuid }) {
//            return entry
//        }
//        return RPGValueEntry(uuid: uuid)
//    }
//
//    // MARK: Photos
//
//    var photoIds: [RPGValuePhoto] {
//        get {
//            guard let all = photos else {
//                return []
//            }
//            return all.sorted { $0.index < $1.index }
//        }
//        set {
//            photos = newValue
//        }
//    }
//
//    func photoOrNew(for id: UUID) -> RPGValuePhoto {
//        if let photo = photoIds.first(where: { $0.uuid == id }) {
//            return photo
//        }
//        return RPGValuePhoto(uuid: id)
//    }
//}
