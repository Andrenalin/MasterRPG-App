// @copyright André Trettin

import AndrenalinKit
import Foundation

struct PhotoEntryModel: Identifiable, Equatable, Hashable, Codable {
    init(id: UUID, photoId: UUID, displayState: Int = 0) {
        self.id = id
        self.photoId = photoId
        self.displayState = displayState
    }

    let id: UUID
    let photoId: UUID

    var displayState: Int = 0
}

extension PhotoEntryModel: EntryDataAccessable {
    var name: String {
        "Photo"
    }
    
    static var empty: PhotoEntryModel { empty(UUID()) }

    static func empty(_ id: UUID) -> PhotoEntryModel {
        PhotoEntryModel(id: id, photoId: UUID())
    }

    func duplicate() -> PhotoEntryModel {
        PhotoEntryModel(id: UUID(), photoId: photoId)
    }
    
    func filter(with search: String) -> Bool {
        true
    }
}

extension PhotoEntryModel: ItemDiffComparable {
    func merge(_ other: PhotoEntryModel) -> PhotoEntryModel {
        PhotoEntryModel(id: id,photoId: other.photoId)
    }

    func isSame(_ other: PhotoEntryModel) -> Bool {
        photoId == other.photoId
    }
}
