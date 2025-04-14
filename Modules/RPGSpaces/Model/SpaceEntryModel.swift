// @copyright André Trettin

import AndrenalinKit
import Foundation

struct SpaceEntryModel: Identifiable, Equatable, Hashable, Codable {
    init(id: UUID, spaceId: UUID, displayState: Int = 0) {
        self.id = id
        self.spaceId = spaceId
        self.displayState = displayState
    }

    let id: UUID
    let spaceId: UUID

    var displayState: Int = 0
}

extension SpaceEntryModel: EntryDataAccessable {
    var name: String {
        "Space Model"
    }
    
    static var empty: SpaceEntryModel { empty(UUID()) }

    static func empty(_ id: UUID) -> SpaceEntryModel {
        SpaceEntryModel(id: id, spaceId: UUID())
    }

    func duplicate() -> SpaceEntryModel {
        SpaceEntryModel(id: UUID(), spaceId: spaceId)
    }
    
    func filter(with search: String) -> Bool {
        true
    }
}

extension SpaceEntryModel: ItemDiffComparable {
    func merge(_ other: SpaceEntryModel) -> SpaceEntryModel {
        SpaceEntryModel(id: id,spaceId: other.spaceId)
    }

    func isSame(_ other: SpaceEntryModel) -> Bool {
        spaceId == other.spaceId
    }
}
