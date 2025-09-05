// @copyright André Trettin

import CoreRPG
import Foundation

struct CharacterModel: Identifiable, Sendable, Codable {
    init(id: UUID, name: String = "", description: String = "", tags: [String] = [], category: ItemListCategory = .character, displayState: Int = 0, photoId: UUID? = nil, photos: [UUID] = [], entries: [CharacterEntryModel] = [], parentId: UUID? = nil) {
        self.id = id
        self.name = name
        self.description = description
        self.tags = tags
        self.category = category
        self.displayState = displayState
        self.photoId = photoId
        self.photos = photos
        self.entries = entries
        self.parentId = parentId
    }

    var id: UUID
    var name: String = ""
    var description: String = ""
    var tags: [String] = []
    var category: ItemListCategory = .character
    var displayState: Int = 0
    var photoId: UUID? = nil
    var photos: [UUID] = []
    var entries: [CharacterEntryModel] = []
    var parentId: UUID? = nil
}

struct CharacterEntryModel: Identifiable, Sendable, Codable {
    init(id: UUID, itemId: UUID, entryId: UUID, index: Int = 0, name: String = "", value: String = "", valueId: UUID? = nil) {
        self.id = id
        self.itemId = itemId
        self.entryId = entryId
        self.index = index
        self.name = name
        self.value = value
        self.valueId = valueId
    }
    
    var id: UUID
    var itemId: UUID
    var entryId: UUID
    var index: Int = 0
    var name: String = ""
    var value: String = ""
    var valueId: UUID? = nil
}
