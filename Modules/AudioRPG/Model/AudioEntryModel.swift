// @copyright André Trettin

import CoreRPG
import Foundation

public struct AudioEntryModel: Identifiable, Equatable, Hashable, Codable, Sendable {
    init(id: UUID, audioId: UUID, displayState: Int = 0) {
        self.id = id
        self.audioId = audioId
        self.displayState = displayState
    }

    public let id: UUID
    public let audioId: UUID

    public var displayState: Int = 0
}

extension AudioEntryModel: EntryDataAccessable {
    public var name: String {
        get { "Track" }
        set {}
    }    
    public var content: String {
        get { "" }
        set {}
    }

    public var childId: UUID { audioId }
    
    public static var empty: AudioEntryModel { empty(UUID()) }
    public static func empty(_ id: UUID) -> AudioEntryModel {
        AudioEntryModel(id: id, audioId: UUID())
    }
    public static func newChild(id: UUID) -> Self {
        AudioEntryModel(id: UUID(), audioId: id)
    }

    public func duplicate() -> AudioEntryModel {
        AudioEntryModel(id: UUID(), audioId: audioId)
    }
    
    public func filter(with search: String) -> Bool {
        true
    }
}

extension AudioEntryModel: ItemDiffComparable {
    public func merge(_ other: AudioEntryModel) -> AudioEntryModel {
        AudioEntryModel(id: id, audioId: other.audioId)
    }

    public func isSame(_ other: AudioEntryModel) -> Bool {
        audioId == other.audioId
    }
}
