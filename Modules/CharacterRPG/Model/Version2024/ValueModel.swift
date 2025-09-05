// @copyright André Trettin

import CoreRPG
import Foundation

struct ValueModel: Equatable, Hashable, Identifiable, Sendable, Codable {
    init(id: UUID, name: CRDT<String>, description: CRDT<String>, tags: CRDT<[String]>, category: CRDT<ItemListCategory>, displayState: Int = 0, photoId: CRDT<UUID?>, photos: CRDTDataUpdate<[UUID]>, entries: CRDTDataUpdate<[ValueEntryModel]>, parentId: UUID?) {
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
    var name: CRDT<String>
    var description: CRDT<String>
    var tags: CRDT<[String]>
    var category: CRDT<ItemListCategory>
    var displayState: Int = 0
    var photoId: CRDT<UUID?>
    var photos: CRDTDataUpdate<[UUID]>
    var entries: CRDTDataUpdate<[ValueEntryModel]>
    var parentId: UUID? = nil
    
    enum CodingKeys: CodingKey {
        case _id
        case _name_
        case _description_
        case _tags_
        case _category_
        case _displayState
        case _photoId_
        case _photos_
        case _entries_
        case _parentId
    }

    func encode(to encoder: Encoder) throws {
        var container: KeyedEncodingContainer<ValueModel.CodingKeys> = encoder.container(keyedBy: ValueModel.CodingKeys.self)

        try container.encode(self.id, forKey: ValueModel.CodingKeys._id)
        try container.encode(self.name, forKey: ValueModel.CodingKeys._name_)
        try container.encode(self.description, forKey: ValueModel.CodingKeys._description_)
        try container.encode(self.tags, forKey: ValueModel.CodingKeys._tags_)
        try container.encode(self.category, forKey: ValueModel.CodingKeys._category_)
        try container.encode(self.displayState, forKey: ValueModel.CodingKeys._displayState)
        try container.encode(self.photoId, forKey: ValueModel.CodingKeys._photoId_)
        try container.encode(self.photos, forKey: ValueModel.CodingKeys._photos_)
        try container.encode(self.entries, forKey: ValueModel.CodingKeys._entries_)
        try container.encode(self.parentId, forKey: ValueModel.CodingKeys._parentId)
    }
    
    init(from decoder: Decoder) throws {
        let container: KeyedDecodingContainer<ValueModel.CodingKeys> = try decoder.container(keyedBy: ValueModel.CodingKeys.self)

        self.id = try container.decode(UUID.self, forKey: ValueModel.CodingKeys._id)
        self.name = try container.decode(CRDT<String>.self, forKey: ValueModel.CodingKeys._name_)
        self.description = try container.decode(CRDT<String>.self, forKey: ValueModel.CodingKeys._description_)
        self.tags = try container.decode(CRDT<[String]>.self, forKey: ValueModel.CodingKeys._tags_)
        self.category = try container.decode(CRDT<ItemListCategory>.self, forKey: ValueModel.CodingKeys._category_)
        self.displayState = try container.decode(Int.self, forKey: ValueModel.CodingKeys._displayState)
        self.photoId = try container.decode(CRDT<UUID?>.self, forKey: ValueModel.CodingKeys._photoId_)
        self.photos = try container.decode(CRDTDataUpdate<[UUID]>.self, forKey: ValueModel.CodingKeys._photos_)
        self.entries = try container.decode(CRDTDataUpdate<[ValueEntryModel]>.self, forKey: ValueModel.CodingKeys._entries_)
    }

}

struct ValueEntryModel: Identifiable, Equatable, Hashable, Codable, Sendable {
    init(id: UUID, name: CRDT<String>, type: CRDT<CharacterEntryDataModel.ValueType>, isGenerator: CRDT<Bool>, value: CRDT<String>, diceId: CRDT<UUID?>, valueId: CRDT<UUID?>, displayState: Int = 0) {
        self.id = id
        _name = name
        _type = type
        _isGenerator = isGenerator
        _value = value
        _diceId = diceId
        _valueId = valueId
        self.displayState = displayState
    }

    let id: UUID
    @CRDT var name: String
    @CRDT var type: CharacterEntryDataModel.ValueType
    @CRDT var isGenerator: Bool
    @CRDT var value: String
    @CRDT var diceId: UUID?
    @CRDT var valueId: UUID?

    var displayState: Int = 0
}
