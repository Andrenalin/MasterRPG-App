// @copyright André Trettin

import AndrenalinKit
import Foundation

public struct SpaceEntryModel: Identifiable, Equatable, Hashable, Codable {
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
        "Space Model"
    }
    
    public static var empty: SpaceEntryModel { empty(UUID()) }

    public static func empty(_ id: UUID) -> SpaceEntryModel {
        SpaceEntryModel(id: id, spaceId: UUID())
    }

    public func duplicate() -> SpaceEntryModel {
        SpaceEntryModel(id: UUID(), spaceId: spaceId)
    }
    
    public func filter(with search: String) -> Bool {
        true
    }
}

extension SpaceEntryModel: ItemDiffComparable {
    public func merge(_ other: SpaceEntryModel) -> SpaceEntryModel {
        SpaceEntryModel(id: id,spaceId: other.spaceId)
    }

    public func isSame(_ other: SpaceEntryModel) -> Bool {
        spaceId == other.spaceId
    }
}
