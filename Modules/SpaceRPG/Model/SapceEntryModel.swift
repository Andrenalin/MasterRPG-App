// @copyright André Trettin

import CoreRPG
import Foundation

public struct SpaceEntryModel: Identifiable, Equatable, Hashable, Codable, Sendable {
    public init(id: UUID, itemId: UUID, displayState: Int = 0) {
        self.id = id
        self.itemId = itemId
        self.displayState = displayState
    }

    public let id: UUID
    public let itemId: UUID

    public var displayState: Int = 0
}

extension SpaceEntryModel: EntryDataAccessable {
    public var name: String {
        "Space"
    }
}
