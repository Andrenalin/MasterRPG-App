// @copyright André Trettin

import AndrenalinKit
import Foundation
import Observation

@Observable
public final class TableModel: Identifiable, @unchecked Sendable {
    init(id: UUID, name: String, description: String = "", tags: [String] = [], category: ItemListCategory = .rules, displayState: Int = 0, tableType: TableModel.TableType = .list, diceId: UUID? = nil, entries: [TableEntryModel], diceResult: String? = nil) {
        self.id = id
        name_ = CRDT(wrappedValue: name)
        description_ = CRDT(wrappedValue: description)
        tags_ = CRDT(wrappedValue: tags)
        category_ = CRDT(wrappedValue: category)
        self.displayState = displayState
        tableType_ = CRDT(wrappedValue: tableType)
        diceId_ = CRDT(wrappedValue: diceId)
        entries_ = CRDTDataUpdate(wrappedValue: entries)
        self.diceResult = diceResult
    }

    init(id: UUID, name: CRDT<String>, description: CRDT<String>, tags: CRDT<[String]>, category: CRDT<ItemListCategory>, displayState: Int = 0, tableType: CRDT<TableModel.TableType>, diceId: CRDT<UUID?>, entries: CRDTDataUpdate<[TableEntryModel]>, diceResult: String? = nil) {
        self.id = id
        name_ = name
        description_ = description
        tags_ = tags
        category_ = category
        self.displayState = displayState
        tableType_ = tableType
        diceId_ = diceId
        entries_ = entries
        self.diceResult = diceResult
    }

    public init(from decoder: Decoder) throws {
        let container: KeyedDecodingContainer<TableModel.CodingKeys> = try decoder.container(keyedBy: TableModel.CodingKeys.self)

        self._id = try container.decode(UUID.self, forKey: TableModel.CodingKeys._id)
        self._name_ = try container.decode(CRDT<String>.self, forKey: TableModel.CodingKeys._name_)
        self._description_ = try container.decode(CRDT<String>.self, forKey: TableModel.CodingKeys._description_)
        self._tags_ = try container.decode(CRDT<[String]>.self, forKey: TableModel.CodingKeys._tags_)
        self._category_ = try container.decode(CRDT<ItemListCategory>.self, forKey: TableModel.CodingKeys._category_)
        self._displayState = try container.decode(Int.self, forKey: TableModel.CodingKeys._displayState)
        self._tableType_ = try container.decode(CRDT<TableModel.TableType>.self, forKey: TableModel.CodingKeys._tableType_)
        self._diceId_ = try container.decode(CRDT<UUID?>.self, forKey: TableModel.CodingKeys._diceId_)
        self._entries_ = try container.decode(CRDTDataUpdate<[TableEntryModel]>.self, forKey: TableModel.CodingKeys._entries_)
        self._diceResult = try container.decodeIfPresent(String.self, forKey: TableModel.CodingKeys._diceResult)
    }

    public enum TableType: Int, Equatable, Hashable, Codable, CaseIterable, Identifiable {
        case list = 0
        case dice = 1
        case all = 2

        public var id: Int {
            rawValue
        }
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

    public var tableType: TableType {
        get { tableType_.wrappedValue }
        set { tableType_.wrappedValue = newValue }
    }
    var tableType_: CRDT<TableType>

    public var diceId: UUID? {
        get { diceId_.wrappedValue }
        set { diceId_.wrappedValue = newValue }
    }
    var diceId_: CRDT<UUID?>

    public var entries: [TableEntryModel] {
        get { entries_.wrappedValue }
        set { entries_.wrappedValue = newValue }
    }
    var entries_: CRDTDataUpdate<[TableEntryModel]>

    var diceResult: String? = nil
}

extension TableModel: Comparable {
    public static func < (lhs: TableModel, rhs: TableModel) -> Bool {
        lhs.name < rhs.name
    }
}

extension TableModel: ItemLinkRegistable {
    @MainActor
    public var linkRegisterModels: [LinkRegisterModel] {
        return entries.reduce([]) { total, entry -> [LinkRegisterModel] in
            let source = ItemRowModel(itemId: id, entryId: entry.id, typeId: .table)
            let models = entry.links(for: entry.content).map {
                LinkRegisterModel(source: source, destination: ItemRowModel(itemId: $0.itemId, entryId: $0.entryId, typeId: $0.module))
            }
            var newTotal = total
            newTotal.append(contentsOf: models)
            return newTotal
        }
    }
}

extension TableModel: ItemDiffComparable {
    public func merge(_ other: TableModel) -> TableModel {
        TableModel(
            id: id,
            name: name_.merged(other: other.name_),
            description: description_.merged(other: other.description_),
            tags: tags_.merged(other: other.tags_),
            category: category_.merged(other: other.category_),
            displayState: other.displayState,
            tableType: tableType_.merged(other: other.tableType_),
            diceId: diceId_.merged(other: other.diceId_),
            entries: entries_.merged(other: other.entries_),
            diceResult: other.diceResult
        )
    }

    public func isSame(_ other: TableModel) -> Bool {
        name == other.name &&
        description == other.description &&
        tags == other.tags &&
        category == other.category &&
        tableType == other.tableType &&
        diceId == other.diceId &&
        entries_.update == other.entries_.update &&
        // santity checks
        entries.count == other.entries.count &&
        entries.enumerated().allSatisfy { index, entry in
            entry == other.entries[index]
        }
    }
}

extension TableModel: ItemDuplicatable {
    public func duplicate() -> TableModel {
        let copyName = duplicateName(from: name)
        return TableModel(id: UUID(), name: copyName, description: description, tags: tags, category: category, displayState: displayState, tableType: tableType, diceId: diceId, entries: entries.map { $0.duplicate() })
    }
}

extension TableModel: ItemReferencable {}

extension TableModel: ItemDataAccessable {
    public var url: URL? { nil }
    public static var empty: TableModel { empty(UUID()) }
    public static func empty(_ id: UUID) -> TableModel {
        TableModel(id: id, name: "", entries: [])
    }
    public static let typeId: NetworkModules = .table

    public func copy() -> TableModel {
        TableModel(id: id, name: name_, description: description_, tags: tags_, category: category_, displayState: displayState, tableType: tableType_, diceId: diceId_, entries: entries_)
    }

    public func filter(_ filter: String) -> Bool {
        (filter.isEmpty || name.localizedCaseInsensitiveContains(filter) || description.localizedCaseInsensitiveContains(filter))
    }

    public func isEqual(other: TableModel) -> Bool {
        self == other
    }

    public var isGroupHiddenToggle: Bool {
        get { isGroupHidden }
        set {
            if newValue {
                displayState = DisplayStateMask.groupHidden.set(on: displayState)
            } else {
                displayState = DisplayStateMask.groupHidden.reset(on: displayState)
            }
        }
    }

    public func replace(with model: TableModel) -> Bool {
        guard self != model else { return false }
        name_ <=> model.name_
        description_ <=> model.description_
        tags_ <=> model.tags_
        category_ <=> model.category_
        displayState <=> model.displayState
        tableType_ <=> model.tableType_
        diceId_ <=> model.diceId_
        entries_ <=> model.entries_
        return true
    }

    public subscript(id: UUID) -> TableEntryModel {
        get {
            guard let index = entries.firstIndex(where: { $0.id == id }) else { return .empty(id) }
            return entries[index]
        }
        set {
            guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
            entries[index] = newValue
        }
    }
}

extension TableModel: Codable {
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

    public final func encode(to encoder: Encoder) throws {
        var container: KeyedEncodingContainer<TableModel.CodingKeys> = encoder.container(keyedBy: TableModel.CodingKeys.self)

        try container.encode(self._id, forKey: TableModel.CodingKeys._id)
        try container.encode(self._name_, forKey: TableModel.CodingKeys._name_)
        try container.encode(self._description_, forKey: TableModel.CodingKeys._description_)
        try container.encode(self._tags_, forKey: TableModel.CodingKeys._tags_)
        try container.encode(self._category_, forKey: TableModel.CodingKeys._category_)
        try container.encode(self._displayState, forKey: TableModel.CodingKeys._displayState)
        try container.encode(self._tableType_, forKey: TableModel.CodingKeys._tableType_)
        try container.encode(self._diceId_, forKey: TableModel.CodingKeys._diceId_)
        try container.encode(self._entries_, forKey: TableModel.CodingKeys._entries_)
        try container.encodeIfPresent(self._diceResult, forKey: TableModel.CodingKeys._diceResult)
    }
}

extension TableModel: Equatable, Hashable {
    public static func == (lhs: TableModel, rhs: TableModel) -> Bool {
        lhs.id == rhs.id && lhs.isSame(rhs) && lhs.displayState == rhs.displayState
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
