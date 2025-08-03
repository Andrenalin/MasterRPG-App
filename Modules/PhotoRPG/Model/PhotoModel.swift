// @copyright André Trettin

import CoreRPG
import Foundation

public struct PhotoModel: Identifiable, Sendable {
    public init(id: UUID, name: CRDT<String>, description: CRDT<String>, tags: CRDT<[String]>, category: CRDT<ItemListCategory>, displayState: Int = 0, degrees: CRDT<Double>, fileUrl: CRDTDataUpdate<FileUrl?>, entries: CRDTDataUpdate<[PhotoEntryModel]>) {
        self.id = id
        name_ = name
        description_ = description
        tags_ = tags
        category_ = category
        self.displayState = displayState
        degrees_ = degrees
        fileUrl_ = fileUrl
        entries_ = entries
    }

    public init(from decoder: Decoder) throws {
        let container: KeyedDecodingContainer<PhotoModel.CodingKeys> = try decoder.container(keyedBy: PhotoModel.CodingKeys.self)

        self.id = try container.decode(UUID.self, forKey: PhotoModel.CodingKeys._id)
        self.name_ = try container.decode(CRDT<String>.self, forKey: PhotoModel.CodingKeys._name_)
        self.description_ = try container.decode(CRDT<String>.self, forKey: PhotoModel.CodingKeys._description_)
        self.tags_ = try container.decode(CRDT<[String]>.self, forKey: PhotoModel.CodingKeys._tags_)
        self.category_ = try container.decode(CRDT<ItemListCategory>.self, forKey: PhotoModel.CodingKeys._category_)
        self.displayState = try container.decode(Int.self, forKey: PhotoModel.CodingKeys._displayState)
        self.degrees_ = try container.decode(CRDT<Double>.self, forKey: PhotoModel.CodingKeys._degrees_)
        self.fileUrl_ = try container.decode(CRDTDataUpdate<FileUrl?>.self, forKey: PhotoModel.CodingKeys._fileUrl_)
        self.entries_ = try container.decode(CRDTDataUpdate<[PhotoEntryModel]>.self, forKey: PhotoModel.CodingKeys._entries_)
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

    public var degrees: Double {
        get { degrees_.wrappedValue }
        set { degrees_.wrappedValue = newValue }
    }
    var degrees_: CRDT<Double>

    public var fileUrl: FileUrl? {
        get { fileUrl_.wrappedValue }
        set { fileUrl_.wrappedValue = newValue }
    }
    var fileUrl_: CRDTDataUpdate<FileUrl?>
    
    public var entries: [PhotoEntryModel] {
        get { entries_.wrappedValue }
        set { entries_.wrappedValue = newValue }
    }
    var entries_: CRDTDataUpdate<[PhotoEntryModel]>
}

extension PhotoModel: Codable {
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
        try container.encode(self.name_, forKey: PhotoModel.CodingKeys._name_)
        try container.encode(self.description_, forKey: PhotoModel.CodingKeys._description_)
        try container.encode(self.tags_, forKey: PhotoModel.CodingKeys._tags_)
        try container.encode(self.category_, forKey: PhotoModel.CodingKeys._category_)
        try container.encode(self.displayState, forKey: PhotoModel.CodingKeys._displayState)
        try container.encode(self.degrees_, forKey: PhotoModel.CodingKeys._degrees_)
        try container.encode(self.fileUrl_, forKey: PhotoModel.CodingKeys._fileUrl_)
        try container.encode(self.entries_, forKey: PhotoModel.CodingKeys._entries_)
    }
}

extension PhotoModel: ItemDataAccessable {
    public static var typeId: NetworkModules {
        .photo
    }
    public var entryModels: [PhotoEntryModel] {
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
    public subscript(id: UUID) -> PhotoEntryModel {
        get { entries.first(where: { $0.id == id }) ?? PhotoEntryModel(id: id, itemId: UUID()) }
        set(newValue) {}
    }
}
