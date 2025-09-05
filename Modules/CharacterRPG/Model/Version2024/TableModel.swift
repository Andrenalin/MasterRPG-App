// @copyright André Trettin

import CoreRPG
import Foundation

struct TableModel: Equatable, Hashable, Identifiable, Sendable, Codable {
    init(id: UUID, name: CRDT<String>, description: CRDT<String>, tags: CRDT<[String]>, category: CRDT<ItemListCategory>, displayState: Int = 0, tableType: CRDT<TableModel.TableType>, diceId: CRDT<UUID?>, entries: CRDTDataUpdate<[TableEntryModel]>, diceResult: String? = nil) {
        self.id = id
        self.name = name
        self.description = description
        self.tags = tags
        self.category = category
        self.displayState = displayState
        self.tableType = tableType
        self.diceId = diceId
        self.entries = entries
    }

    var id: UUID
    var name: CRDT<String>
    var description: CRDT<String>
    var tags: CRDT<[String]>
    var category: CRDT<ItemListCategory>
    var displayState: Int
    var tableType: CRDT<TableType>
    var diceId: CRDT<UUID?>
    var entries: CRDTDataUpdate<[TableEntryModel]>
    
    var diceResult: String? = nil
    
    public enum TableType: Int, Equatable, Hashable, Codable, CaseIterable, Identifiable, Sendable {
        case list = 0
        case dice = 1
        case all = 2

        public var id: Int {
            rawValue
        }
    }
    
    enum CodingKeys: CodingKey {
        case _id
        case _name_
        case _description_
        case _tags_
        case _category_
        case _displayState
        case _tableType_
        case _diceId_
        case _entries_
        case _diceResult
    }

    func encode(to encoder: Encoder) throws {
        var container: KeyedEncodingContainer<TableModel.CodingKeys> = encoder.container(keyedBy: TableModel.CodingKeys.self)

        try container.encode(self.id, forKey: TableModel.CodingKeys._id)
        try container.encode(self.name, forKey: TableModel.CodingKeys._name_)
        try container.encode(self.description, forKey: TableModel.CodingKeys._description_)
        try container.encode(self.tags, forKey: TableModel.CodingKeys._tags_)
        try container.encode(self.category, forKey: TableModel.CodingKeys._category_)
        try container.encode(self.displayState, forKey: TableModel.CodingKeys._displayState)
        try container.encode(self.tableType, forKey: TableModel.CodingKeys._tableType_)
        try container.encode(self.diceId, forKey: TableModel.CodingKeys._diceId_)
        try container.encode(self.entries, forKey: TableModel.CodingKeys._entries_)
        try container.encodeIfPresent(self.diceResult, forKey: TableModel.CodingKeys._diceResult)
    }
    
    init(from decoder: Decoder) throws {
        let container: KeyedDecodingContainer<TableModel.CodingKeys> = try decoder.container(keyedBy: TableModel.CodingKeys.self)

        self.id = try container.decode(UUID.self, forKey: TableModel.CodingKeys._id)
        self.name = try container.decode(CRDT<String>.self, forKey: TableModel.CodingKeys._name_)
        self.description = try container.decode(CRDT<String>.self, forKey: TableModel.CodingKeys._description_)
        self.tags = try container.decode(CRDT<[String]>.self, forKey: TableModel.CodingKeys._tags_)
        self.category = try container.decode(CRDT<ItemListCategory>.self, forKey: TableModel.CodingKeys._category_)
        self.displayState = try container.decode(Int.self, forKey: TableModel.CodingKeys._displayState)
        self.tableType = try container.decode(CRDT<TableModel.TableType>.self, forKey: TableModel.CodingKeys._tableType_)
        self.diceId = try container.decode(CRDT<UUID?>.self, forKey: TableModel.CodingKeys._diceId_)
        self.entries = try container.decode(CRDTDataUpdate<[TableEntryModel]>.self, forKey: TableModel.CodingKeys._entries_)
        self.diceResult = try container.decodeIfPresent(String.self, forKey: TableModel.CodingKeys._diceResult)
    }
}

struct TableEntryModel: Equatable, Hashable, Identifiable, Sendable, Codable {
    init(id: UUID, name: CRDT<String>, content: CRDT<String>, displayState: Int, diceResult: String?) {
        self.id = id
        _name = name
        _content = content
        self.displayState = displayState
        self.diceResult = diceResult
    }

    let id: UUID
    @CRDT var name: String
    @CRDT var content: String
    var displayState: Int = 0

    var diceResult: String? = nil
}
