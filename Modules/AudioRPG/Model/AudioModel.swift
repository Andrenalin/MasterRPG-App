// @copyright André Trettin

import CoreRPG
import Foundation

public struct AudioModel: Identifiable, Sendable {
    init(id: UUID, name: CRDT<String>, description: CRDT<String>, tags: CRDT<[String]>, category: CRDT<ItemListCategory>, displayState: Int = 0, fileUrl: CRDTDataUpdate<FileUrl?>, entries: CRDTDataUpdate<[AudioEntryModel]>) {
        self.id = id
        name_ = name
        description_ = description
        tags_ = tags
        category_ = category
        self.displayState = displayState
        fileUrl_ = fileUrl
        entries_ = entries
    }

    public init(from decoder: Decoder) throws {
        let container: KeyedDecodingContainer<AudioModel.CodingKeys> = try decoder.container(keyedBy: AudioModel.CodingKeys.self)

        self.id = try container.decode(UUID.self, forKey: AudioModel.CodingKeys._id)
        self.name_ = try container.decode(CRDT<String>.self, forKey: AudioModel.CodingKeys._name_)
        self.description_ = try container.decode(CRDT<String>.self, forKey: AudioModel.CodingKeys._description_)
        self.tags_ = try container.decode(CRDT<[String]>.self, forKey: AudioModel.CodingKeys._tags_)
        self.category_ = try container.decode(CRDT<ItemListCategory>.self, forKey: AudioModel.CodingKeys._category_)
        self.displayState = try container.decode(Int.self, forKey: AudioModel.CodingKeys._displayState)
        self.fileUrl_ = try container.decode(CRDTDataUpdate<FileUrl?>.self, forKey: AudioModel.CodingKeys._fileUrl_)
        self.entries_ = try container.decode(CRDTDataUpdate<[AudioEntryModel]>.self, forKey: AudioModel.CodingKeys._entries_)
    }

    public var id: UUID

    public var name: String {
        get { name_.wrappedValue }
        set { name_.wrappedValue = newValue }
    }
    var name_: CRDT<String>

    public var description: String {
        get { description_.wrappedValue }
        set { description_.wrappedValue = newValue }
    }
    var description_: CRDT<String>

    public var tags: [String] {
        get { tags_.wrappedValue }
        set { tags_.wrappedValue = newValue }
    }
    var tags_: CRDT<[String]>

    public var category: ItemListCategory {
        get { category_.wrappedValue }
        set { category_.wrappedValue = newValue }
    }
    var category_: CRDT<ItemListCategory>

    public var displayState: Int

    public var fileUrl: FileUrl? {
        get { fileUrl_.wrappedValue }
        set { fileUrl_.wrappedValue = newValue }
    }
    var fileUrl_: CRDTDataUpdate<FileUrl?>
    
    public var entries: [AudioEntryModel] {
        get { entries_.wrappedValue }
        set { entries_.wrappedValue = newValue }
    }
    var entries_: CRDTDataUpdate<[AudioEntryModel]>
}

extension AudioModel: Codable {
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

    public func encode(to encoder: Encoder) throws {
        var container: KeyedEncodingContainer<AudioModel.CodingKeys> = encoder.container(keyedBy: AudioModel.CodingKeys.self)

        try container.encode(self.id, forKey: AudioModel.CodingKeys._id)
        try container.encode(self.name_, forKey: AudioModel.CodingKeys._name_)
        try container.encode(self.description_, forKey: AudioModel.CodingKeys._description_)
        try container.encode(self.tags_, forKey: AudioModel.CodingKeys._tags_)
        try container.encode(self.category_, forKey: AudioModel.CodingKeys._category_)
        try container.encode(self.displayState, forKey: AudioModel.CodingKeys._displayState)
        try container.encode(self.fileUrl_, forKey: AudioModel.CodingKeys._fileUrl_)
        try container.encode(self.entries_, forKey: AudioModel.CodingKeys._entries_)
    }
}

extension AudioModel: ItemDataAccessable {
    public static var typeId: NetworkModules {
        .audio
    }
    public var entryModels: [AudioEntryModel] {
        get { entries }
        set(newValue) { entries = newValue }
    }
    public var information: String {
        get { description }
        set(newValue) { description = newValue }
    }
    public var url: URL? {
        get { nil }
        set(newValue) {}
    }
    public var parentId: UUID? {
        get { nil }
        set(newValue) {}
    }
    
    public func reset(name: String) {}
    public func reset(information: String) {}
    public func reset(url: URL?) {}
    public subscript(id: UUID) -> AudioEntryModel {
        get { entries.first(where: { $0.id == id }) ?? AudioEntryModel(id: id, itemId: UUID()) }
        set(newValue) {}
    }
}
