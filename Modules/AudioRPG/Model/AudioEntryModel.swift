// @copyright André Trettin

import CoreRPG
import Foundation

struct AudioEntryModel: Identifiable, Equatable, Hashable, Codable, Sendable {
    init(id: UUID, photoId: UUID, displayState: Int = 0) {
        self.id = id
        self.photoId = photoId
        self.displayState = displayState
    }

    public let id: UUID
    public let photoId: UUID

    public var displayState: Int = 0
}

extension AudioEntryModel: EntryDataAccessable {
    public var name: String {
        "Photo"
    }
}
