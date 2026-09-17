// @copyright André Trettin

import CoreRPG
import Foundation
import Observation

// MainActor-owned model. Sendable via global-actor isolation (no @unchecked):
// persistence crosses the Core Data boundary as TableSnapshot,
// the .gmz wire format stays on this type's Codable (encode/decode on MainActor).
//
// Split across three files — this one (init + stored properties),
// TableModel+Links.swift (ItemLinkRegistable), and
// TableModel+Persistence.swift (ItemDiffComparable/Codable/ItemDataAccessable
// and their canonical-content helper types) — since the single 418-line
// original mixed several loosely related, mostly boilerplate-driven
// protocol conformances. See CODE_AUDIT_Table §9.10.
@MainActor @Observable
public final class TableModel: nonisolated Identifiable {
    nonisolated init(id: UUID, name: String, description: String = "", tags: [String] = [], category: ItemListCategory = .rules, displayState: Int = 0, tableType: TableModel.TableType = .list, diceId: UUID? = nil, entries: [TableEntryModel], diceResult: String? = nil, parentId: UUID? = nil) {
        self.id = id
        _name_ = CRDT(wrappedValue: name)
        _description_ = CRDT(wrappedValue: description)
        _tags_ = CRDT(wrappedValue: tags)
        _category_ = CRDT(wrappedValue: category)
        self._displayState = displayState
        _tableType_ = CRDT(wrappedValue: tableType)
        _diceId_ = CRDT(wrappedValue: diceId)
        _entries_ = CRDTDataUpdate(wrappedValue: entries)
        self._diceResult = diceResult
        self._parentId = parentId
    }

    nonisolated init(id: UUID, name: CRDT<String>, description: CRDT<String>, tags: CRDT<[String]>, category: CRDT<ItemListCategory>, displayState: Int = 0, tableType: CRDT<TableModel.TableType>, diceId: CRDT<UUID?>, entries: CRDTDataUpdate<[TableEntryModel]>, diceResult: String? = nil, parentId: UUID?) {
        self.id = id
        _name_ = name
        _description_ = description
        _tags_ = tags
        _category_ = category
        self._displayState = displayState
        _tableType_ = tableType
        _diceId_ = diceId
        _entries_ = entries
        self._diceResult = diceResult
        self._parentId = parentId
    }

    nonisolated public init(from decoder: Decoder) throws {
        let container: KeyedDecodingContainer<TableModel.CodingKeys> = try decoder.container(keyedBy: TableModel.CodingKeys.self)

        self.id = try container.decode(UUID.self, forKey: TableModel.CodingKeys._id)
        self._name_ = try container.decode(CRDT<String>.self, forKey: TableModel.CodingKeys._name_)
        self._description_ = try container.decode(CRDT<String>.self, forKey: TableModel.CodingKeys._description_)
        self._tags_ = try container.decode(CRDT<[String]>.self, forKey: TableModel.CodingKeys._tags_)
        self._category_ = try container.decode(CRDT<ItemListCategory>.self, forKey: TableModel.CodingKeys._category_)
        self._displayState = try container.decode(Int.self, forKey: TableModel.CodingKeys._displayState)
        self._tableType_ = try container.decode(CRDT<TableModel.TableType>.self, forKey: TableModel.CodingKeys._tableType_)
        self._diceId_ = try container.decode(CRDT<UUID?>.self, forKey: TableModel.CodingKeys._diceId_)
        self._entries_ = try container.decode(CRDTDataUpdate<[TableEntryModel]>.self, forKey: TableModel.CodingKeys._entries_)
        self._diceResult = try container.decodeIfPresent(String.self, forKey: TableModel.CodingKeys._diceResult)
        self._parentId = try container.decodeIfPresent(UUID.self, forKey: TableModel.CodingKeys._parentId)
    }

    public enum TableType: Int, Equatable, Hashable, Codable, CaseIterable, Identifiable, Sendable {
        case list = 0
        case dice = 1
        case all = 2

        public var id: Int {
            rawValue
        }
    }

    // `let`: nonisolated access (Identifiable, hashing) per SE-0434.
    public let id: UUID
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

    public var parentId: UUID? = nil
}

extension TableModel: nonisolated Comparable {
    nonisolated public static func < (lhs: TableModel, rhs: TableModel) -> Bool {
        return assumeMainActorIsolated {
            lhs.name < rhs.name

        }
    }
}

// Kept in this file (rather than split out with the rest of the persistence
// conformances into TableModel+Persistence.swift) because `encode(to:)`
// reaches past the @Observable-computed accessors into the macro's
// synthesized backing storage (`_name_` etc.), which is file-private to
// where the tracked properties are declared. See CODE_AUDIT_Table §9.10.
extension TableModel: nonisolated Codable {
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
        case _parentId
    }

    nonisolated public final func encode(to encoder: Encoder) throws {
        try encoder.encodeOnMainActor { encoder in
            var container: KeyedEncodingContainer<TableModel.CodingKeys> = encoder.container(keyedBy: TableModel.CodingKeys.self)

            try container.encode(self.id, forKey: TableModel.CodingKeys._id)
            try container.encode(self._name_, forKey: TableModel.CodingKeys._name_)
            try container.encode(self._description_, forKey: TableModel.CodingKeys._description_)
            try container.encode(self._tags_, forKey: TableModel.CodingKeys._tags_)
            try container.encode(self._category_, forKey: TableModel.CodingKeys._category_)
            try container.encode(self._displayState, forKey: TableModel.CodingKeys._displayState)
            try container.encode(self._tableType_, forKey: TableModel.CodingKeys._tableType_)
            try container.encode(self._diceId_, forKey: TableModel.CodingKeys._diceId_)
            try container.encode(self._entries_, forKey: TableModel.CodingKeys._entries_)
            try container.encodeIfPresent(self._diceResult, forKey: TableModel.CodingKeys._diceResult)
            try container.encodeIfPresent(self._parentId, forKey: TableModel.CodingKeys._parentId)

        }
    }
}

extension TableModel: nonisolated ItemDataAccessable {
    public var fileUrl: FileUrl? {
        get { nil }
        set(newValue) {}
    }

    nonisolated public static var empty: TableModel { empty(UUID()) }
    nonisolated public static func empty(_ id: UUID) -> TableModel {
        TableModel(id: id, name: "", entries: [])
    }
    nonisolated public static let typeId: NetworkModules = .table

    public func copy() -> TableModel {
        TableModel(id: id, name: name_, description: description_, tags: tags_, category: category_, displayState: displayState, tableType: tableType_, diceId: diceId_, entries: entries_, parentId: parentId)
    }

    public func filter(filter: String, includeEntries: Bool) -> Bool {
        guard !filter.isEmpty else { return true }
        guard !(name.localizedCaseInsensitiveContains(filter) || description.localizedCaseInsensitiveContains(filter)) else { return true }
        guard specialCategory == false else { return false }
        return entries.contains {
            $0.filter(with: filter)
        }
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

    @MainActor public func replace(with model: TableModel) -> Bool {
        guard self != model else { return false }
        name_ <=> model.name_
        description_ <=> model.description_
        tags_ <=> model.tags_
        category_ <=> model.category_
        displayState <=> model.displayState
        tableType_ <=> model.tableType_
        diceId_ <=> model.diceId_
        entries_ <=> model.entries_
        parentId <=> model.parentId
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
