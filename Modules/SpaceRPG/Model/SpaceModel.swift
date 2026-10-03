// @copyright André Trettin

import CoreRPG
import Foundation
import Observation

// MainActor-owned model. Sendable via global-actor isolation (no @unchecked):
// persistence crosses the Core Data boundary as SpaceSnapshot,
// the .gmz wire format stays on this type's Codable (encode/decode on MainActor).
@MainActor @Observable
public final class SpaceModel: nonisolated Identifiable {
    nonisolated init(id: UUID, name: String, description: String = "", tags: [String] = [], category: ItemListCategory = .item, displayState: Int, degrees: Double = 0, fileUrl: FileUrl? = nil, entries: [SpaceEntryModel] = [], parentId: UUID? = nil) {
        self.id = id
        _name_ = CRDT(wrappedValue: name)
        _description_ = CRDT(wrappedValue: description)
        _tags_ = CRDT(wrappedValue: tags)
        _category_ = CRDT(wrappedValue: category)
        self._displayState = displayState
        _degrees_ = CRDT(wrappedValue: degrees)
        _fileUrl_ = CRDTDataUpdate(wrappedValue: fileUrl)
        _entries_ = CRDTDataUpdate(wrappedValue: entries)
        self._parentId = parentId
    }

    nonisolated init(id: UUID, name: CRDT<String>, description: CRDT<String>, tags: CRDT<[String]>, category: CRDT<ItemListCategory>, displayState: Int, degrees: CRDT<Double>, fileUrl: CRDTDataUpdate<FileUrl?>, entries: CRDTDataUpdate<[SpaceEntryModel]>, parentId: UUID?) {
        self.id = id
        _name_ = name
        _description_ = description
        _tags_ = tags
        _category_ = category
        self._displayState = displayState
        _degrees_ = degrees
        _fileUrl_ = fileUrl
        _entries_ = entries
        self._parentId = parentId
    }

    nonisolated public init(from decoder: Decoder) throws {
        let container: KeyedDecodingContainer<SpaceModel.CodingKeys> = try decoder.container(keyedBy: SpaceModel.CodingKeys.self)

        self.id = try container.decode(UUID.self, forKey: SpaceModel.CodingKeys._id)
        self._name_ = try container.decode(CRDT<String>.self, forKey: SpaceModel.CodingKeys._name_)
        self._description_ = try container.decode(CRDT<String>.self, forKey: SpaceModel.CodingKeys._description_)
        self._tags_ = try container.decode(CRDT<[String]>.self, forKey: SpaceModel.CodingKeys._tags_)
        self._category_ = try container.decode(CRDT<ItemListCategory>.self, forKey: SpaceModel.CodingKeys._category_)
        self._displayState = try container.decode(Int.self, forKey: SpaceModel.CodingKeys._displayState)
        self._degrees_ = try container.decode(CRDT<Double>.self, forKey: SpaceModel.CodingKeys._degrees_)
        self._fileUrl_ = try container.decode(CRDTDataUpdate<FileUrl?>.self, forKey: SpaceModel.CodingKeys._fileUrl_)
        self._entries_ = try container.decode(CRDTDataUpdate<[SpaceEntryModel]>.self, forKey: SpaceModel.CodingKeys._entries_)
        self._parentId = try container.decodeIfPresent(UUID.self, forKey: SpaceModel.CodingKeys._parentId)
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
    
    public var entries: [SpaceEntryModel] {
        get { entries_.wrappedValue }
        set { entries_.wrappedValue = newValue }
    }
    var entries_: CRDTDataUpdate<[SpaceEntryModel]>

    public var parentId: UUID? = nil
    
    // only game properties
    public var players: [UUID] = []
}

extension SpaceModel: nonisolated Comparable {
    nonisolated public static func < (lhs: SpaceModel, rhs: SpaceModel) -> Bool {
        return assumeMainActorIsolated {
            lhs.name < rhs.name
    
        }
    }
}

extension SpaceModel: nonisolated ItemGameReportable {}
extension SpaceModel: nonisolated ItemLinkRegistrable {}

extension SpaceModel: nonisolated ItemDiffComparable {
    nonisolated public func merge(_ other: SpaceModel) -> SpaceModel {
        return assumeMainActorIsolated {
            let mergedCategory = category_.merged(other: other.category_)
            // Folders union their members, other categories last-writer-wins. See CODE_AUDIT_Folder §9.8.
            let mergedEntries = FolderEntryMerge.mergedEntries(category: mergedCategory.wrappedValue, local: entries_, remote: other.entries_, id: \.id, name: \.name, childId: \.childId)
            return SpaceModel(
                id: id,
                name: name_.merged(other: other.name_),
                description: description_.merged(other: other.description_),
                tags: tags_.merged(other: other.tags_),
                category: mergedCategory,
                displayState: other.displayState,
                degrees: degrees_.merged(other: other.degrees_),
                fileUrl: fileUrl_.merged(other: other.fileUrl_),
                entries: mergedEntries,
                parentId: other.parentId
            )
    
        }
    }

    nonisolated public func isSame(_ other: SpaceModel) -> Bool {
        return assumeMainActorIsolated {
            name == other.name &&
            description == other.description &&
            tags == other.tags &&
            category == other.category &&
            degrees == other.degrees &&
            fileUrl_.update == other.fileUrl_.update &&
            entries_.update == other.entries_.update &&
            parentId == other.parentId
    
        }
    }
    
    public var version: Int {
        fileUrl?.contentVersion ?? FileUrl.versionValue(of: fileUrl_.update)
    }
}

// MARK: - Review Properties

extension SpaceModel {
    @MainActor public var reviewProperties: [ReviewCustomProperty] {
        [
            ReviewCustomProperty(displayName: String(localized: "Rotation", bundle: .module)) {
                ReviewPropertyValue(($0 as? SpaceModel)?.degrees ?? 0)
            }
        ]
    }
}

extension SpaceModel: nonisolated ItemDuplicatable {
    nonisolated public func duplicate() -> SpaceModel {
        return assumeMainActorIsolated {
            let copyName = duplicateName(from: name)
            // The copy starts outside any folder; the duplicate flow files it. See CODE_AUDIT_Folder §5.27.
            return SpaceModel(id: UUID(), name: copyName, description: description, tags: tags, category: category, displayState: displayState, degrees: degrees, fileUrl: nil, entries: entries.map { $0.duplicate() }, parentId: nil)
    
        }
    }
}

extension SpaceModel: nonisolated ItemDataAccessible {
    nonisolated public static var empty: SpaceModel { empty(UUID()) }
    nonisolated public static func empty(_ id: UUID) -> SpaceModel {
        SpaceModel(id: id, name: "", displayState: 0)
    }
    nonisolated public static let typeId: NetworkModules = .space

    public func copy() -> SpaceModel {
        SpaceModel(id: id, name: name_, description: description_, tags: tags_, category: category_, displayState: displayState, degrees: degrees_, fileUrl: fileUrl_, entries: entries_, parentId: parentId)
    }
    
    public func filter(filter: String, includeEntries: Bool) -> Bool {
        guard !filter.isEmpty else { return true }
        guard !(name.localizedStandardContains(filter) || description.localizedStandardContains(filter)) else { return true }
        return false
    }

    public func isEqual(other: SpaceModel) -> Bool {
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

    @MainActor public func replace(with model: SpaceModel) -> Bool {
        guard self != model else { return false }
        name_ <=> model.name_
        description_ <=> model.description_
        tags_ <=> model.tags_
        category_ <=> model.category_
        displayState <=> model.displayState
        degrees_ <=> model.degrees_
        fileUrl_ <=> model.fileUrl_
        entries_ <=> model.entries_
        parentId <=> model.parentId
        return true
    }

    public subscript(id: UUID) -> SpaceEntryModel {
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

extension SpaceModel: nonisolated Codable {
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
        case _parentId
    }

    nonisolated public final func encode(to encoder: Encoder) throws {
        try encoder.encodeOnMainActor { encoder in
            var container: KeyedEncodingContainer<SpaceModel.CodingKeys> = encoder.container(keyedBy: SpaceModel.CodingKeys.self)

            try container.encode(self.id, forKey: SpaceModel.CodingKeys._id)
            try container.encode(self._name_, forKey: SpaceModel.CodingKeys._name_)
            try container.encode(self._description_, forKey: SpaceModel.CodingKeys._description_)
            try container.encode(self._tags_, forKey: SpaceModel.CodingKeys._tags_)
            try container.encode(self._category_, forKey: SpaceModel.CodingKeys._category_)
            try container.encode(self._displayState, forKey: SpaceModel.CodingKeys._displayState)
            try container.encode(self._degrees_, forKey: SpaceModel.CodingKeys._degrees_)
            try container.encode(self._fileUrl_, forKey: SpaceModel.CodingKeys._fileUrl_)
            try container.encode(self._entries_, forKey: SpaceModel.CodingKeys._entries_)
            try container.encodeIfPresent(self._parentId, forKey: SpaceModel.CodingKeys._parentId)
    
        }
    }
}

extension SpaceModel: nonisolated Equatable, nonisolated Hashable {
    nonisolated public static func == (lhs: SpaceModel, rhs: SpaceModel) -> Bool {
        return assumeMainActorIsolated {
            lhs.id == rhs.id && lhs.isSame(rhs) && lhs.displayState == rhs.displayState
    
        }
    }

    nonisolated public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
