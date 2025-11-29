// @copyright André Trettin

import CoreRPG
import Foundation

public struct PhotoEntryModel: Identifiable, Equatable, Hashable, Codable {
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
        get { "Photo" }
        set {}
    }
    
    public var childId: UUID { photoId }
    
    public static var empty: PhotoEntryModel { empty(UUID()) }
    public static func newChild(id: UUID) -> Self {
        PhotoEntryModel(id: UUID(), photoId: id)
    }

    static func empty(_ id: UUID) -> PhotoEntryModel {
        PhotoEntryModel(id: id, photoId: UUID())
    }

    public func duplicate() -> PhotoEntryModel {
        PhotoEntryModel(id: UUID(), photoId: photoId)
    }
    
    public func filter(with search: String) -> Bool {
        true
    }
}

extension PhotoEntryModel: ItemDiffComparable {
    public func merge(_ other: PhotoEntryModel) -> PhotoEntryModel {
        PhotoEntryModel(id: id,photoId: other.photoId)
    }

    public func isSame(_ other: PhotoEntryModel) -> Bool {
        photoId == other.photoId
    }
}
