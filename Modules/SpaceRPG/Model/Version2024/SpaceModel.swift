// @copyright André Trettin

import CoreRPG
import Foundation

struct SpaceModel: Equatable, Hashable, Identifiable, Sendable, Codable {
    init(id: UUID, name: CRDT<String>, description: CRDT<String>, tags: CRDT<[String]>, category: CRDT<ItemListCategory>, displayState: Int = 0, fileUrl: CRDTDataUpdate<FileUrl?>, entries: CRDTDataUpdate<[SpaceEntryModel]>) {
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
    var name: CRDT<String>
    var description: CRDT<String>
    var tags: CRDT<[String]>
    var category: CRDT<ItemListCategory>
    var displayState: Int
    var fileUrl: CRDTDataUpdate<FileUrl?>
    var entries: CRDTDataUpdate<[SpaceEntryModel]>
    
    enum CodingKeys: CodingKey {
        case _id
        case _name_
        case _description_
        case _tags_
        case _category_
        case _displayState
        case _degrees_
        case _fileUrl_
        case _entries_
    }

    func encode(to encoder: Encoder) throws {
        var container: KeyedEncodingContainer<SpaceModel.CodingKeys> = encoder.container(keyedBy: SpaceModel.CodingKeys.self)

        try container.encode(self.id, forKey: SpaceModel.CodingKeys._id)
        try container.encode(self.name, forKey: SpaceModel.CodingKeys._name_)
        try container.encode(self.description, forKey: SpaceModel.CodingKeys._description_)
        try container.encode(self.tags, forKey: SpaceModel.CodingKeys._tags_)
        try container.encode(self.category, forKey: SpaceModel.CodingKeys._category_)
        try container.encode(self.displayState, forKey: SpaceModel.CodingKeys._displayState)
        try container.encode(CRDT<Double>(wrappedValue: 0.0), forKey: SpaceModel.CodingKeys._degrees_)
        try container.encode(self.fileUrl, forKey: SpaceModel.CodingKeys._fileUrl_)
        try container.encode(self.entries, forKey: SpaceModel.CodingKeys._entries_)
    }
    
    init(from decoder: Decoder) throws {
        let container: KeyedDecodingContainer<SpaceModel.CodingKeys> = try decoder.container(keyedBy: SpaceModel.CodingKeys.self)

        self.id = try container.decode(UUID.self, forKey: SpaceModel.CodingKeys._id)
        self.name = try container.decode(CRDT<String>.self, forKey: SpaceModel.CodingKeys._name_)
        self.description = try container.decode(CRDT<String>.self, forKey: SpaceModel.CodingKeys._description_)
        self.tags = try container.decode(CRDT<[String]>.self, forKey: SpaceModel.CodingKeys._tags_)
        self.category = try container.decode(CRDT<ItemListCategory>.self, forKey: SpaceModel.CodingKeys._category_)
        self.displayState = try container.decode(Int.self, forKey: SpaceModel.CodingKeys._displayState)
        self.fileUrl = try container.decode(CRDTDataUpdate<FileUrl?>.self, forKey: SpaceModel.CodingKeys._fileUrl_)
        self.entries = try container.decode(CRDTDataUpdate<[SpaceEntryModel]>.self, forKey: SpaceModel.CodingKeys._entries_)
    }
}

struct SpaceEntryModel: Equatable, Hashable, Identifiable, Sendable, Codable {
    init(id: UUID, spaceId: UUID, displayState: Int = 0) {
        self.id = id
        self.spaceId = spaceId
        self.displayState = displayState
    }

    let id: UUID
    let spaceId: UUID

    var displayState: Int = 0
}


