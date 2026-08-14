// @copyright André Trettin

import CoreRPG
import Foundation
import Observation

// MainActor-owned model. Sendable via global-actor isolation (no @unchecked):
// persistence crosses the Core Data boundary as TableSnapshot,
// the .gmz wire format stays on this type's Codable (encode/decode on MainActor).
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
        return MainActor.assumeIsolated {
            lhs.name < rhs.name
    
        }
    }
}

extension TableModel: nonisolated ItemLinkRegistable {
    @MainActor public var linkRegisterModels: [LinkRegisterModel] {
        changedLinkRegisterModels(oldValue: .empty).0
    }

    @MainActor public func changedLinkRegisterModels(oldValue: TableModel) -> (added: [LinkRegisterModel], removed: [LinkRegisterModel]) {
        var added: [LinkRegisterModel] = []
        var removed: [LinkRegisterModel] = []
        
        if oldValue.diceId != diceId {
            let modelSource = ItemRowModel(itemId: id, typeId: .table)
            if let diceId = diceId {
                added.append(LinkRegisterModel(name: "", source: modelSource, destination: ItemRowModel(itemId: diceId, typeId: .dice)))
            }
            if let oldDiceId = oldValue.diceId {
                removed.append(LinkRegisterModel(name: "", source: modelSource, destination: ItemRowModel(itemId: oldDiceId, typeId: .dice)))
            }
        }

        if oldValue.entries != entries {
            let addedEntryIds = Set(entries.map(\.id)).subtracting(Set(oldValue.entries.map(\.id)))
            let removedEntryIds = Set(oldValue.entries.map(\.id)).subtracting(Set(entries.map(\.id)))
            addedEntryIds.forEach {
                added.append(contentsOf: linkRegisterModels(entry: self[$0]))
            }
            removedEntryIds.forEach {
                removed.append(contentsOf: linkRegisterModels(entry: oldValue[$0]))
            }
            let sameEntryIds = Set(entries.map(\.id)).intersection(Set(oldValue.entries.map(\.id)))
            sameEntryIds.forEach {
                let oldEntry = oldValue[$0]
                let newEntry = self[$0]
                if oldEntry != newEntry {
                    removed.append(contentsOf: linkRegisterModels(entry: oldEntry, valueChanged: oldEntry.content != newEntry.content))
                    added.append(contentsOf: linkRegisterModels(entry: newEntry, valueChanged: oldEntry.content != newEntry.content))
                }
            }
        }
        
        return (added, removed)
    }
    
    @MainActor func linkRegisterModels(entry: TableEntryModel, valueChanged: Bool = true) -> [LinkRegisterModel] {
        let source = ItemRowModel(itemId: id, entryId: entry.id, typeId: .table)
        var total: [LinkRegisterModel] = []
        if valueChanged {
            total += entry.links(for: entry.content).map {
                LinkRegisterModel(link: $0, source: source)
            }
        }
        return total
    }
}

extension TableModel: nonisolated ItemDiffComparable {
    nonisolated public func merge(_ other: TableModel) -> TableModel {
        return MainActor.assumeIsolated {
            let mergedCategory = category_.merged(other: other.category_)
            let mergedEntries: CRDTDataUpdate<[TableEntryModel]>
            if mergedCategory.wrappedValue == .folder {
                let allIds = Set(entries.map(\.id)).union(other.entries.map(\.id))
                let combined = allIds
                    .compactMap { id in entries.first { $0.id == id } ?? other.entries.first { $0.id == id } }
                    .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
                mergedEntries = CRDTDataUpdate(wrappedValue: combined)
            } else {
                mergedEntries = entries_.merged(other: other.entries_)
            }
            return TableModel(
                id: id,
                name: name_.merged(other: other.name_),
                description: description_.merged(other: other.description_),
                tags: tags_.merged(other: other.tags_),
                category: mergedCategory,
                displayState: other.displayState,
                tableType: tableType_.merged(other: other.tableType_),
                diceId: diceId_.merged(other: other.diceId_),
                entries: mergedEntries,
                diceResult: other.diceResult,
                parentId: other.parentId
            )
    
        }
    }

    nonisolated public func isSame(_ other: TableModel) -> Bool {
        return MainActor.assumeIsolated {
            name == other.name &&
            description == other.description &&
            tags == other.tags &&
            category == other.category &&
            tableType == other.tableType &&
            diceId == other.diceId &&
            entries_.update == other.entries_.update &&
            parentId == other.parentId &&
            // santity checks
            entries.count == other.entries.count &&
            entries.enumerated().allSatisfy { index, entry in
                entry == other.entries[index]
            }
    
        }
    }

    /// Deterministic identity of the Table content sent by the game master.
    /// Dice results are presentation-only game state and must not force a new
    /// package version when somebody rolls the same Table.
    public var version: Int {
        StableVersionDigest.digest(CanonicalTableContent(self))
    }
}

private struct CanonicalTableContent: Codable, Sendable {
    let id: UUID
    let name: String
    let description: String
    let tags: [String]
    let category: ItemListCategory
    let displayState: Int
    let tableType: TableModel.TableType
    let diceId: UUID?
    let entries: [CanonicalTableEntry]
    let parentId: UUID?

    @MainActor
    init(_ model: TableModel) {
        id = model.id
        name = model.name
        description = model.description
        tags = model.tags
        category = model.category
        displayState = model.displayState
        tableType = model.tableType
        diceId = model.diceId
        entries = model.entries.map(CanonicalTableEntry.init)
        parentId = model.parentId
    }
}

private struct CanonicalTableEntry: Codable, Sendable {
    let id: UUID
    let name: String
    let content: String
    let displayState: Int

    init(_ entry: TableEntryModel) {
        id = entry.id
        name = entry.name
        content = entry.content
        displayState = entry.displayState
    }
}

// MARK: - Review Properties

extension TableModel {
    @MainActor public var reviewProperties: [ReviewCustomProperty] {
        [
            ReviewCustomProperty(displayName: String(localized: "Table Type", bundle: .module)) {
                .option("\(($0 as? TableModel)?.tableType ?? TableType.list)")
            },
            ReviewCustomProperty(displayName: String(localized: "Dice", bundle: .module)) {
                ReviewPropertyValue(diceId: ($0 as? TableModel)?.diceId)
            }
        ]
    }
}

extension TableModel: nonisolated ItemDuplicatable {
    nonisolated public func duplicate() -> TableModel {
        return MainActor.assumeIsolated {
            let copyName = duplicateName(from: name)
            return TableModel(id: UUID(), name: copyName, description: description, tags: tags, category: category, displayState: displayState, tableType: tableType, diceId: diceId, entries: entries.map { $0.duplicate() }, parentId: nil)
    
        }
    }
}

extension TableModel: nonisolated ItemReferencable {}

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

extension TableModel: nonisolated Equatable, nonisolated Hashable {
    nonisolated public static func == (lhs: TableModel, rhs: TableModel) -> Bool {
        return MainActor.assumeIsolated {
            lhs.id == rhs.id && lhs.isSame(rhs) && lhs.displayState == rhs.displayState
    
        }
    }

    nonisolated public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
