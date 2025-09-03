// @copyright André Trettin

import CoreRPG
import Foundation

struct SpaceModel: Identifiable, Sendable, Codable {
    init(id: UUID, name: String = "", description: String = "", tags: [String] = [], category: ItemListCategory = .item, displayState: Int = 0, degrees: Double = 0, fileUrl: FileUrl? = nil, entries: [SpaceEntryModel] = []) {
        self.id = id
        self.name = name
        self.description = description
        self.tags = tags
        self.category = category
        self.displayState = displayState
        self.degrees = degrees
        self.fileUrl = fileUrl
        self.entries = entries
    }

    var id: UUID
    var name: String = ""
    var description: String = ""
    var tags: [String] = []
    var category: ItemListCategory = .item
    var displayState: Int = 0
    var degrees: Double = 0
    var fileUrl: FileUrl? = nil
    var entries: [SpaceEntryModel] = []
}

struct SpaceEntryModel: Identifiable, Sendable, Codable {
    init(id: UUID, name: String = "", displayState: Int = 0) {
        self.id = id
        self.name = name
        self.displayState = displayState
    }
    
    var id: UUID
    var name: String = ""
    var displayState: Int = 0
}
