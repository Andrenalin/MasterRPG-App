// @copyright André Trettin

import CoreRPG
import Foundation

struct AudioModel: Equatable, Hashable, Identifiable, Sendable, Codable {
    init(id: UUID, name: CRDT<String>, description: CRDT<String>, tags: CRDT<[String]>, category: CRDT<ItemListCategory>, displayState: Int = 0, fileUrl: CRDTDataUpdate<FileUrl?>, entries: CRDTDataUpdate<[AudioEntryModel]>) {
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
    var entries: CRDTDataUpdate<[AudioEntryModel]>
    
    enum CodingKeys: CodingKey {
        case _id
        case _name_
        case _description_
        case _tags_
        case _category_
        case _displayState
        case _fileUrl_
        case _entries_
    }

    public init(from decoder: Decoder) throws {
        let container: KeyedDecodingContainer<AudioModel.CodingKeys> = try decoder.container(keyedBy: AudioModel.CodingKeys.self)

        self.id = try container.decode(UUID.self, forKey: AudioModel.CodingKeys._id)
        self.name = try container.decode(CRDT<String>.self, forKey: AudioModel.CodingKeys._name_)
        self.description = try container.decode(CRDT<String>.self, forKey: AudioModel.CodingKeys._description_)
        self.tags = try container.decode(CRDT<[String]>.self, forKey: AudioModel.CodingKeys._tags_)
        self.category = try container.decode(CRDT<ItemListCategory>.self, forKey: AudioModel.CodingKeys._category_)
        self.displayState = try container.decode(Int.self, forKey: AudioModel.CodingKeys._displayState)
        self.fileUrl = try container.decode(CRDTDataUpdate<FileUrl?>.self, forKey: AudioModel.CodingKeys._fileUrl_)
        self.entries = try container.decode(CRDTDataUpdate<[AudioEntryModel]>.self, forKey: AudioModel.CodingKeys._entries_)
    }

    public func encode(to encoder: Encoder) throws {
        var container: KeyedEncodingContainer<AudioModel.CodingKeys> = encoder.container(keyedBy: AudioModel.CodingKeys.self)

        try container.encode(self.id, forKey: AudioModel.CodingKeys._id)
        try container.encode(self.name, forKey: AudioModel.CodingKeys._name_)
        try container.encode(self.description, forKey: AudioModel.CodingKeys._description_)
        try container.encode(self.tags, forKey: AudioModel.CodingKeys._tags_)
        try container.encode(self.category, forKey: AudioModel.CodingKeys._category_)
        try container.encode(self.displayState, forKey: AudioModel.CodingKeys._displayState)
        try container.encode(self.fileUrl, forKey: AudioModel.CodingKeys._fileUrl_)
        try container.encode(self.entries, forKey: AudioModel.CodingKeys._entries_)
    }
}

struct AudioEntryModel: Equatable, Hashable, Identifiable, Sendable, Codable {
    init(id: UUID, audioId: UUID, displayState: Int = 0) {
        self.id = id
        self.audioId = audioId
        self.displayState = displayState
    }
    
    var id: UUID
    var audioId: UUID
    var displayState: Int = 0
}
