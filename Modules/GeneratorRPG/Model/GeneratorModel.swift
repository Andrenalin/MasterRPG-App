// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftUI

// MainActor-owned model. Sendable via global-actor isolation (no @unchecked):
// persistence crosses the Core Data boundary as GeneratorSnapshot.
@MainActor @Observable
final class GeneratorModel: nonisolated Identifiable {
    nonisolated init(id: UUID, name: String, description: String = "", tags: [String] = [], category: ItemListCategory = .item, displayState: Int, entries: [ChildEntryModel] = [], parentId: UUID? = nil, genType: GenType = .adventure, referenceId: UUID? = nil) {
        self.id = id
        _name_ = CRDT(wrappedValue: name)
        _description_ = CRDT(wrappedValue: description)
        _tags_ = CRDT(wrappedValue: tags)
        _category_ = CRDT(wrappedValue: category)
        self._displayState = displayState
        _entries_ = CRDTDataUpdate(wrappedValue: entries)
        self._parentId = parentId
        self._genType = genType
        self._referenceId = referenceId
    }

    nonisolated init(id: UUID, name: CRDT<String>, description: CRDT<String>, tags: CRDT<[String]>, category: CRDT<ItemListCategory>, displayState: Int, entries: CRDTDataUpdate<[ChildEntryModel]>, parentId: UUID?, genType: GenType, referenceId: UUID?) {
        self.id = id
        _name_ = name
        _description_ = description
        _tags_ = tags
        _category_ = category
        self._displayState = displayState
        _entries_ = entries
        self._parentId = parentId
        self._genType = genType
        self._referenceId = referenceId
    }

    nonisolated init(from decoder: Decoder) throws {
        let container: KeyedDecodingContainer<GeneratorModel.CodingKeys> = try decoder.container(keyedBy: GeneratorModel.CodingKeys.self)

        self.id = try container.decode(UUID.self, forKey: GeneratorModel.CodingKeys._id)
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

    // `let`: nonisolated access (Identifiable, hashing) per SE-0434.
    let id: UUID

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
        
        var title: LocalizedStringResource {
            switch self {
            case .adventure:
                LocalizedStringResource("Adventure", bundle: .module)
            case .character:
                LocalizedStringResource("Character", bundle: .module)
            case .extractor:
                LocalizedStringResource("Extractor", bundle: .module)
            }
        }
    }
}

extension GeneratorModel: nonisolated ItemLinkRegistrable {}

extension GeneratorModel: nonisolated ItemDiffComparable {
    nonisolated func merge(_ other: GeneratorModel) -> GeneratorModel {
        return assumeMainActorIsolated {
            let mergedCategory = category_.merged(other: other.category_)
            let mergedEntries: CRDTDataUpdate<[ChildEntryModel]>
            if mergedCategory.wrappedValue == .folder {
                // Deterministic union (name, then id). See CODE_AUDIT_18 §9.9.
                let combined = FolderEntryMerge.merged(local: entries, remote: other.entries, id: \.id, name: \.name, childId: \.childId)
                mergedEntries = CRDTDataUpdate(wrappedValue: combined)
            } else {
                mergedEntries = entries_.merged(other: other.entries_)
            }
            return GeneratorModel(
                id: id,
                name: name_.merged(other: other.name_),
                description: description_.merged(other: other.description_),
                tags: tags_.merged(other: other.tags_),
                category: mergedCategory,
                displayState: other.displayState,
                entries: mergedEntries,
                parentId: other.parentId,
                genType: other.genType,
                referenceId: other.referenceId
            )
    
        }
    }

    nonisolated func isSame(_ other: GeneratorModel) -> Bool {
        return assumeMainActorIsolated {
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
}

extension GeneratorModel: nonisolated ItemDuplicatable {
    nonisolated func duplicate() -> GeneratorModel {
        return assumeMainActorIsolated {
            let copyName = duplicateName(from: name)
            // The copy starts outside any folder; the duplicate flow files it. See CODE_AUDIT_Folder §5.27.
            return GeneratorModel(id: UUID(), name: copyName, description: description, tags: tags, category: category, displayState: displayState, entries: entries.map { $0.duplicate() }, parentId: nil, genType: genType, referenceId: referenceId)
    
        }
    }
}

extension GeneratorModel: nonisolated ItemDataAccessible {
    public var fileUrl: FileUrl? {
        get { nil }
        set(newValue) {}
    }

    nonisolated public static var empty: GeneratorModel { empty(UUID()) }
    nonisolated public static func empty(_ id: UUID) -> GeneratorModel {
        GeneratorModel(id: id, name: "", displayState: 0)
    }
    nonisolated public static let typeId: NetworkModules = .generator

    public func copy() -> GeneratorModel {
        GeneratorModel(id: id, name: name_, description: description_, tags: tags_, category: category_, displayState: displayState, entries: entries_, parentId: parentId, genType: genType, referenceId: referenceId)
    }
    
    public func filter(filter: String, includeEntries: Bool) -> Bool {
        (filter.isEmpty || name.localizedStandardContains(filter) || description.localizedStandardContains(filter))
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

extension GeneratorModel: nonisolated Equatable, nonisolated Hashable, nonisolated Comparable, nonisolated Codable {
    nonisolated static func == (lhs: GeneratorModel, rhs: GeneratorModel) -> Bool {
        return assumeMainActorIsolated {
            lhs.id == rhs.id && lhs.isSame(rhs) && lhs.displayState == rhs.displayState
    
        }
    }
    
    nonisolated static func < (lhs: GeneratorModel, rhs: GeneratorModel) -> Bool {
        return assumeMainActorIsolated {
            lhs.name < rhs.name
    
        }
    }
    
    nonisolated func hash(into hasher: inout Hasher) {
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

    nonisolated final func encode(to encoder: Encoder) throws {
        try encoder.encodeOnMainActor { encoder in
            var container: KeyedEncodingContainer<GeneratorModel.CodingKeys> = encoder.container(keyedBy: GeneratorModel.CodingKeys.self)

            try container.encode(self.id, forKey: GeneratorModel.CodingKeys._id)
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
}
