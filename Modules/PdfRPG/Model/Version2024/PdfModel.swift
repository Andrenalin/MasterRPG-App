// @copyright André Trettin

import CoreRPG
import Foundation
import CoreGraphics

struct PdfModel: Equatable, Hashable, Identifiable, Sendable, Codable {
    init(id: UUID, name: CRDT<String>, description: CRDT<String>, tags: CRDT<[String]>, category: CRDT<ItemListCategory>, displayState: Int = 0, fileUrl: CRDTDataUpdate<FileUrl?>, entries: CRDTDataUpdate<[PdfEntryModel]>) {
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
    var entries: CRDTDataUpdate<[PdfEntryModel]>
    
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
        let container: KeyedDecodingContainer<PdfModel.CodingKeys> = try decoder.container(keyedBy: PdfModel.CodingKeys.self)

        self.id = try container.decode(UUID.self, forKey: PdfModel.CodingKeys._id)
        self.name = try container.decode(CRDT<String>.self, forKey: PdfModel.CodingKeys._name_)
        self.description = try container.decode(CRDT<String>.self, forKey: PdfModel.CodingKeys._description_)
        self.tags = try container.decode(CRDT<[String]>.self, forKey: PdfModel.CodingKeys._tags_)
        self.category = try container.decode(CRDT<ItemListCategory>.self, forKey: PdfModel.CodingKeys._category_)
        self.displayState = try container.decode(Int.self, forKey: PdfModel.CodingKeys._displayState)
        self.fileUrl = try container.decode(CRDTDataUpdate<FileUrl?>.self, forKey: PdfModel.CodingKeys._fileUrl_)
        self.entries = try container.decode(CRDTDataUpdate<[PdfEntryModel]>.self, forKey: PdfModel.CodingKeys._entries_)
    }

    public func encode(to encoder: Encoder) throws {
        var container: KeyedEncodingContainer<PdfModel.CodingKeys> = encoder.container(keyedBy: PdfModel.CodingKeys.self)

        try container.encode(self.id, forKey: PdfModel.CodingKeys._id)
        try container.encode(self.name, forKey: PdfModel.CodingKeys._name_)
        try container.encode(self.description, forKey: PdfModel.CodingKeys._description_)
        try container.encode(self.tags, forKey: PdfModel.CodingKeys._tags_)
        try container.encode(self.category, forKey: PdfModel.CodingKeys._category_)
        try container.encode(self.displayState, forKey: PdfModel.CodingKeys._displayState)
        try container.encode(self.fileUrl, forKey: PdfModel.CodingKeys._fileUrl_)
        try container.encode(self.entries, forKey: PdfModel.CodingKeys._entries_)
    }
}

struct PdfEntryModel: Equatable, Hashable, Identifiable, Sendable, Codable {
    init(id: UUID, name: CRDT<String>, content: CRDT<String>, pageNumber: String, bounds: CGRect = .zero, displayState: Int) {
        self.id = id
        _name = name
        _content = content
        self.pageLabel = pageNumber
        self.bounds = bounds
        self.displayState = displayState
    }

    let id: UUID
    @CRDT var name: String
    @CRDT var content: String
    var pageLabel: String
    var bounds: CGRect
    var displayState: Int = 0
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(name)
        hasher.combine(content)
        hasher.combine(pageLabel)
    }
}
