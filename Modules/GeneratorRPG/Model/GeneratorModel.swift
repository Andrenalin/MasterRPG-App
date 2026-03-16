// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftUI

@Observable
final class GeneratorModel: Identifiable, @unchecked Sendable {
    init(id: UUID, name: String, description: String = "", tags: [String] = [], category: ItemListCategory = .item, displayState: Int, entries: [ChildEntryModel] = [], parentId: UUID? = nil, genType: GenType = .adventure, referenceId: UUID? = nil) {
        self.id = id
        name_ = CRDT(wrappedValue: name)
        description_ = CRDT(wrappedValue: description)
        tags_ = CRDT(wrappedValue: tags)
        category_ = CRDT(wrappedValue: category)
        self.displayState = displayState
        entries_ = CRDTDataUpdate(wrappedValue: entries)
        self.parentId = parentId
        self.genType = genType
        self.referenceId = referenceId
    }

    init(id: UUID, name: CRDT<String>, description: CRDT<String>, tags: CRDT<[String]>, category: CRDT<ItemListCategory>, displayState: Int, entries: CRDTDataUpdate<[ChildEntryModel]>, parentId: UUID?, genType: GenType, referenceId: UUID?) {
        self.id = id
        name_ = name
        description_ = description
        tags_ = tags
        category_ = category
        self.displayState = displayState
        entries_ = entries
        self.parentId = parentId
        self.genType = genType
        self.referenceId = referenceId
    }

    init(from decoder: Decoder) throws {
        let container: KeyedDecodingContainer<GeneratorModel.CodingKeys> = try decoder.container(keyedBy: GeneratorModel.CodingKeys.self)

        self._id = try container.decode(UUID.self, forKey: GeneratorModel.CodingKeys._id)
        self._name_ = try container.decode(CRDT<String>.self, forKey: GeneratorModel.CodingKeys._name_)
        self._description_ = try container.decode(CRDT<String>.self, forKey: GeneratorModel.CodingKeys._description_)
        self._tags_ = try container.decode(CRDT<[String]>.self, forKey: GeneratorModel.CodingKeys._tags_)
        self._category_ = try container.decode(CRDT<ItemListCategory>.self, forKey: GeneratorModel.CodingKeys._category_)
        self._displayState = try container.decode(Int.self, forKey: GeneratorModel.CodingKeys._displayState)
        self._entries_ = try container.decode(CRDTDataUpdate<[ChildEntryModel]>.self, forKey: GeneratorModel.CodingKeys._entries_)
        self._parentId = try container.decodeIfPresent(UUID.self, forKey: GeneratorModel.CodingKeys._parentId)
        self._genType = try container.decode(GenType.self, forKey: GeneratorModel.CodingKeys._genType)
        self._referenceId = try container.decodeIfPresent(UUID.self, forKey: GeneratorModel.CodingKeys._referenceId)
    }

    var id: UUID

    var name: String {
        get { name_.wrappedValue }
        set { name_.wrappedValue = newValue }
    }
    var name_: CRDT<String>

    var description: String {
        get { description_.wrappedValue }
        set { description_.wrappedValue = newValue }
    }
    var description_: CRDT<String>

    var tags: [String] {
        get { tags_.wrappedValue }
        set { tags_.wrappedValue = newValue }
    }
    var tags_: CRDT<[String]>

    var category: ItemListCategory {
        get { category_.wrappedValue }
        set { category_.wrappedValue = newValue }
    }
    var category_: CRDT<ItemListCategory>

    var displayState: Int

    var entries: [ChildEntryModel] {
        get { entries_.wrappedValue }
        set { entries_.wrappedValue = newValue }
    }
    var entries_: CRDTDataUpdate<[ChildEntryModel]>

    var parentId: UUID? = nil
    
    // Generator Properties
    var genType: GenType = .adventure
    var referenceId: UUID?
}

extension GeneratorModel {
    enum GenType: Int, Equatable, Hashable, Sendable, Codable, CaseIterable, Identifiable {
        var id: Int {
            rawValue
        }
        
        case adventure = 0
        case character = 1
        case extractor = 2
        
        var title: LocalizedStringKey {
            switch self {
            case .adventure: "Adventure"
            case .character: "Character"
            case .extractor: "Extractor"
            }
        }
    }
}

extension GeneratorModel: ItemLinkRegistable {}

extension GeneratorModel: ItemDiffComparable {
    func merge(_ other: GeneratorModel) -> GeneratorModel {
        GeneratorModel(
            id: id,
            name: name_.merged(other: other.name_),
            description: description_.merged(other: other.description_),
            tags: tags_.merged(other: other.tags_),
            category: category_.merged(other: other.category_),
            displayState: other.displayState,
            entries: entries_.merged(other: other.entries_),
            parentId: other.parentId,
            genType: other.genType,
            referenceId: other.referenceId
        )
    }

    func isSame(_ other: GeneratorModel) -> Bool {
        name == other.name &&
        description == other.description &&
        tags == other.tags &&
        category == other.category &&
        entries_.update == other.entries_.update &&
        parentId == other.parentId &&
        genType == other.genType &&
        referenceId == other.referenceId
    }
}

extension GeneratorModel: ItemDuplicatable {
    func duplicate() -> GeneratorModel {
        let copyName = duplicateName(from: name)
        return GeneratorModel(id: UUID(), name: copyName, description: description, tags: tags, category: category, displayState: displayState, entries: entries.map { $0.duplicate() }, parentId: parentId, genType: genType, referenceId: referenceId)
    }
}

extension GeneratorModel: ItemDataAccessable {
    public var fileUrl: FileUrl? {
        get { nil }
        set(newValue) {}
    }

    public static var empty: GeneratorModel { empty(UUID()) }
    public static func empty(_ id: UUID) -> GeneratorModel {
        GeneratorModel(id: id, name: "", displayState: 0)
    }
    public static let typeId: NetworkModules = .generator

    public func copy() -> GeneratorModel {
        GeneratorModel(id: id, name: name_, description: description_, tags: tags_, category: category_, displayState: displayState, entries: entries_, parentId: parentId, genType: genType, referenceId: referenceId)
    }
    
    public func filter(filter: String, includeEntries: Bool) -> Bool {
        (filter.isEmpty || name.localizedCaseInsensitiveContains(filter) || description.localizedCaseInsensitiveContains(filter))
    }
    
    public func isEqual(other: GeneratorModel) -> Bool {
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

    @MainActor public func replace(with model: GeneratorModel) -> Bool {
        guard self != model else { return false }
        name_ <=> model.name_
        description_ <=> model.description_
        tags_ <=> model.tags_
        category_ <=> model.category_
        displayState <=> model.displayState
        entries_ <=> model.entries_
        parentId <=> model.parentId
        genType <=> model.genType
        referenceId <=> model.referenceId
        return true
    }

    public subscript(id: UUID) -> ChildEntryModel {
        get {
            guard let index = entries.firstIndex(where: { $0.id == id }) else { return .empty(id) }
            return entries[index]
        }
        set {
            guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
            entries[index] = newValue
        }
    }

    public func urlName(entryId: UUID) -> String {
        " \(name.withoutLink())-\(entries.firstIndex(where: { $0.id == entryId } ) ?? 0)"
    }
}

extension GeneratorModel: Equatable, Hashable, Comparable, Codable {
    static func == (lhs: GeneratorModel, rhs: GeneratorModel) -> Bool {
        lhs.id == rhs.id && lhs.isSame(rhs) && lhs.displayState == rhs.displayState
    }
    
    static func < (lhs: GeneratorModel, rhs: GeneratorModel) -> Bool {
        lhs.name < rhs.name
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    enum CodingKeys: CodingKey {
        case _id
        case _name_
        case _description_
        case _tags_
        case _category_
        case _displayState
        case _entries_
        case _parentId
        case _genType
        case _referenceId
    }

    final func encode(to encoder: Encoder) throws {
        var container: KeyedEncodingContainer<GeneratorModel.CodingKeys> = encoder.container(keyedBy: GeneratorModel.CodingKeys.self)

        try container.encode(self._id, forKey: GeneratorModel.CodingKeys._id)
        try container.encode(self._name_, forKey: GeneratorModel.CodingKeys._name_)
        try container.encode(self._description_, forKey: GeneratorModel.CodingKeys._description_)
        try container.encode(self._tags_, forKey: GeneratorModel.CodingKeys._tags_)
        try container.encode(self._category_, forKey: GeneratorModel.CodingKeys._category_)
        try container.encode(self._displayState, forKey: GeneratorModel.CodingKeys._displayState)
        try container.encode(self._entries_, forKey: GeneratorModel.CodingKeys._entries_)
        try container.encodeIfPresent(self._parentId, forKey: GeneratorModel.CodingKeys._parentId)
        try container.encode(self._genType, forKey: GeneratorModel.CodingKeys._genType)
        try container.encodeIfPresent(self._referenceId, forKey: GeneratorModel.CodingKeys._referenceId)
    }
}
