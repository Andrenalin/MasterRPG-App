// @copyright André Trettin

import CoreRPG
import Foundation

struct AudioModel: Identifiable, Sendable, Codable {
    init(id: UUID, name: String = "", description: String = "", tags: [String] = [], category: ItemListCategory = .music, displayState: Int = 0, fileUrl: FileUrl? = nil, entries: [AudioEntryModel] = []) {
        self.id = id
        self.name = name
        self.description = description
        self.tags = tags
        self.category = category
        self.displayState = displayState
        self.fileUrl = fileUrl
        self.entries = entries
    }

    var id: UUID
    var name: String = ""
    var description: String = ""
    var tags: [String] = []
    var category: ItemListCategory = .music
    var displayState: Int = 0
    var fileUrl: FileUrl? = nil
    var entries: [AudioEntryModel] = []
}

struct AudioEntryModel: Identifiable, Sendable, Codable {
    init(id: UUID, audioId: UUID, displayState: Int = 0) {
        self.id = id
        self.audioId = audioId
        self.displayState = displayState
    }
    
    var id: UUID
    var audioId: UUID
    var displayState: Int = 0
}
