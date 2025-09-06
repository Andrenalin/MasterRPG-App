// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftUI

struct AdventureModel: Equatable, Hashable, Identifiable, Sendable, Codable {
    init(id: UUID, name: CRDT<String>, description: CRDT<String>, tags: CRDT<[String]>, category: CRDT<ItemListCategory>, displayState: Int = 0, photoId: CRDT<UUID?>, entries: CRDTDataUpdate<[AdventureEntryModel]>) {
        self.id = id
        self.name = name
        self.description = description
        self.tags = tags
        self.category = category
        self.displayState = displayState
        self.photoId = photoId
        self.entries = entries
    }

    var id: UUID
    var name: CRDT<String>
    var description: CRDT<String>
    var tags: CRDT<[String]>
    var category: CRDT<ItemListCategory>
    var displayState: Int
    var photoId: CRDT<UUID?>
    var entries: CRDTDataUpdate<[AdventureEntryModel]>

    enum CodingKeys: CodingKey {
        case _id
        case _name_
        case _description_
        case _tags_
        case _category_
        case _displayState
        case _photoId_
        case _entries_
    }

    func encode(to encoder: Encoder) throws {
        var container: KeyedEncodingContainer<AdventureModel.CodingKeys> = encoder.container(keyedBy: AdventureModel.CodingKeys.self)

        try container.encode(self.id, forKey: AdventureModel.CodingKeys._id)
        try container.encode(self.name, forKey: AdventureModel.CodingKeys._name_)
        try container.encode(self.description, forKey: AdventureModel.CodingKeys._description_)
        try container.encode(self.tags, forKey: AdventureModel.CodingKeys._tags_)
        try container.encode(self.category, forKey: AdventureModel.CodingKeys._category_)
        try container.encode(self.displayState, forKey: AdventureModel.CodingKeys._displayState)
        try container.encode(self.photoId, forKey: AdventureModel.CodingKeys._photoId_)
        try container.encode(self.entries, forKey: AdventureModel.CodingKeys._entries_)
    }
    
    init(from decoder: Decoder) throws {
        let container: KeyedDecodingContainer<AdventureModel.CodingKeys> = try decoder.container(keyedBy: AdventureModel.CodingKeys.self)

        self.id = try container.decode(UUID.self, forKey: AdventureModel.CodingKeys._id)
        self.name = try container.decode(CRDT<String>.self, forKey: AdventureModel.CodingKeys._name_)
        self.description = try container.decode(CRDT<String>.self, forKey: AdventureModel.CodingKeys._description_)
        self.tags = try container.decode(CRDT<[String]>.self, forKey: AdventureModel.CodingKeys._tags_)
        self.category = try container.decode(CRDT<ItemListCategory>.self, forKey: AdventureModel.CodingKeys._category_)
        self.displayState = try container.decode(Int.self, forKey: AdventureModel.CodingKeys._displayState)
        self.photoId = try container.decode(CRDT<UUID?>.self, forKey: AdventureModel.CodingKeys._photoId_)
        self.entries = try container.decode(CRDTDataUpdate<[AdventureEntryModel]>.self, forKey: AdventureModel.CodingKeys._entries_)
    }
}

struct AdventureEntryModel: Equatable, Hashable, Identifiable, Sendable, Codable {
    init(id: UUID, name: CRDT<String>, content: CRDT<String>, displayState: Int = 0) {
        self.id = id
        _name = name
        _content = content
        self.displayState = displayState
    }

    var id: UUID
    @CRDT var name: String
    @CRDT var content: String
    var displayState: Int
}
