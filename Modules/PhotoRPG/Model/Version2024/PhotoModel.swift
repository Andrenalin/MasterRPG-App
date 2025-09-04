// @copyright André Trettin

import CoreRPG
import Foundation

struct PhotoModel: Equatable, Hashable, Identifiable, Sendable, Codable {
    init(id: UUID, name: CRDT<String>, description: CRDT<String>, tags: CRDT<[String]>, category: CRDT<ItemListCategory>, displayState: Int = 0, degrees: CRDT<Double> = CRDT<Double>(wrappedValue: 0.0), fileUrl: CRDTDataUpdate<FileUrl?>, entries: CRDTDataUpdate<[PhotoEntryModel]>) {
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
    var name: CRDT<String>
    var description: CRDT<String>
    var tags: CRDT<[String]>
    var category: CRDT<ItemListCategory>
    var displayState: Int
    var degrees: CRDT<Double> = CRDT<Double>(wrappedValue: 0.0)
    var fileUrl: CRDTDataUpdate<FileUrl?>
    var entries: CRDTDataUpdate<[PhotoEntryModel]>
    
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

    public func encode(to encoder: Encoder) throws {
        var container: KeyedEncodingContainer<PhotoModel.CodingKeys> = encoder.container(keyedBy: PhotoModel.CodingKeys.self)

        try container.encode(self.id, forKey: PhotoModel.CodingKeys._id)
        try container.encode(self.name, forKey: PhotoModel.CodingKeys._name_)
        try container.encode(self.description, forKey: PhotoModel.CodingKeys._description_)
        try container.encode(self.tags, forKey: PhotoModel.CodingKeys._tags_)
        try container.encode(self.category, forKey: PhotoModel.CodingKeys._category_)
        try container.encode(self.displayState, forKey: PhotoModel.CodingKeys._displayState)
        try container.encode(self.degrees, forKey: PhotoModel.CodingKeys._degrees_)
        try container.encode(self.fileUrl, forKey: PhotoModel.CodingKeys._fileUrl_)
        try container.encode(self.entries, forKey: PhotoModel.CodingKeys._entries_)
    }
    
    public init(from decoder: Decoder) throws {
        let container: KeyedDecodingContainer<PhotoModel.CodingKeys> = try decoder.container(keyedBy: PhotoModel.CodingKeys.self)

        self.id = try container.decode(UUID.self, forKey: PhotoModel.CodingKeys._id)
        self.name = try container.decode(CRDT<String>.self, forKey: PhotoModel.CodingKeys._name_)
        self.description = try container.decode(CRDT<String>.self, forKey: PhotoModel.CodingKeys._description_)
        self.tags = try container.decode(CRDT<[String]>.self, forKey: PhotoModel.CodingKeys._tags_)
        self.category = try container.decode(CRDT<ItemListCategory>.self, forKey: PhotoModel.CodingKeys._category_)
        self.displayState = try container.decode(Int.self, forKey: PhotoModel.CodingKeys._displayState)
        self.degrees = try container.decode(CRDT<Double>.self, forKey: PhotoModel.CodingKeys._degrees_)
        self.fileUrl = try container.decode(CRDTDataUpdate<FileUrl?>.self, forKey: PhotoModel.CodingKeys._fileUrl_)
        self.entries = try container.decode(CRDTDataUpdate<[PhotoEntryModel]>.self, forKey: PhotoModel.CodingKeys._entries_)
    }
}

struct PhotoEntryModel: Equatable, Hashable, Identifiable, Sendable, Codable {
    init(id: UUID, photoId: UUID, displayState: Int = 0) {
        self.id = id
        self.photoId = photoId
        self.displayState = displayState
    }
    
    let id: UUID
    let photoId: UUID
    var displayState: Int = 0
}
