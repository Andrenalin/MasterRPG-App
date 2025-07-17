// @copyright André Trettin

import CoreRPG
import Foundation

struct SpaceEntryModel: Identifiable, Equatable, Hashable, Codable, Sendable {
    init(id: UUID, spaceId: UUID, displayState: Int = 0) {
        self.id = id
        self.spaceId = spaceId
        self.displayState = displayState
    }

    public let id: UUID
    public let spaceId: UUID

    public var displayState: Int = 0
}

extension SpaceEntryModel: EntryDataAccessable {
    public var name: String {
        "Space"
    }
}
