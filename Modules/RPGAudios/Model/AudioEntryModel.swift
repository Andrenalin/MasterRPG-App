// @copyright André Trettin

import AndrenalinKit
import Foundation

struct AudioEntryModel: Identifiable, Equatable, Hashable, Codable {
    init(id: UUID, audioId: UUID, displayState: Int = 0) {
        self.id = id
        self.audioId = audioId
        self.displayState = displayState
    }

    let id: UUID
    let audioId: UUID

    var displayState: Int = 0
}

extension AudioEntryModel: ItemDiffComparable {
    func merge(_ other: AudioEntryModel) -> AudioEntryModel {
        AudioEntryModel(
            id: id,
            audioId: other.audioId
        )
    }

    func isSame(_ other: AudioEntryModel) -> Bool {
        audioId == other.audioId
    }
}

extension AudioEntryModel: EntryDataAccessable {
    var name: String {
        "Track"
    }
    
    static var empty: AudioEntryModel { empty(UUID()) }
    static func empty(_ id: UUID) -> AudioEntryModel {
        AudioEntryModel(id: id, audioId: UUID())
    }

    func duplicate() -> AudioEntryModel {
        AudioEntryModel(id: UUID(), audioId: audioId)
    }
    
    func filter(with search: String) -> Bool {
        true
    }
}
