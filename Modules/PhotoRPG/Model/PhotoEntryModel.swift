// @copyright André Trettin

import CoreRPG
import Foundation

struct PhotoEntryModel: Identifiable, Equatable, Hashable, Codable, Sendable {
    init(id: UUID, photoId: UUID, displayState: Int = 0) {
        self.id = id
        self.photoId = photoId
        self.displayState = displayState
    }

    public let id: UUID
    public let photoId: UUID

    public var displayState: Int = 0
}

extension PhotoEntryModel: EntryDataAccessable {
    public var name: String {
        "Photo"
    }
}

//extension PhotoEntryModel: ItemDiffComparable {
//    public func merge(_ other: PhotoEntryModel) -> PhotoEntryModel {
//        PhotoEntryModel(id: id,photoId: other.photoId)
//    }
//
//    public func isSame(_ other: PhotoEntryModel) -> Bool {
//        photoId == other.photoId
//    }
//}
