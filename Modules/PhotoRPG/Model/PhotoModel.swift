// @copyright André Trettin

import CoreRPG
import Foundation
import Observation

// MainActor-owned model. Sendable via global-actor isolation (no @unchecked):
// persistence crosses the Core Data boundary as PhotoSnapshot,
// the .gmz wire format stays on this type's Codable (encode/decode on MainActor).
@MainActor @Observable
public final class PhotoModel: nonisolated Identifiable {
    nonisolated init(id: UUID, name: String, description: String = "", tags: [String] = [], category: ItemListCategory = .adventure, displayState: Int = 0, degrees: Double = 0, fileUrl: FileUrl? = nil, entries: [PhotoEntryModel] = [], parentId: UUID? = nil) {
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

    nonisolated init(id: UUID, name: CRDT<String>, description: CRDT<String>, tags: CRDT<[String]>, category: CRDT<ItemListCategory>, displayState: Int = 0, degrees: CRDT<Double>, fileUrl: CRDTDataUpdate<FileUrl?>, entries: CRDTDataUpdate<[PhotoEntryModel]>, parentId: UUID?) {
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
        let container: KeyedDecodingContainer<PhotoModel.CodingKeys> = try decoder.container(keyedBy: PhotoModel.CodingKeys.self)

        self.id = try container.decode(UUID.self, forKey: PhotoModel.CodingKeys._id)
        self._name_ = try container.decode(CRDT<String>.self, forKey: PhotoModel.CodingKeys._name_)
        self._description_ = try container.decode(CRDT<String>.self, forKey: PhotoModel.CodingKeys._description_)
        self._tags_ = try container.decode(CRDT<[String]>.self, forKey: PhotoModel.CodingKeys._tags_)
        self._category_ = try container.decode(CRDT<ItemListCategory>.self, forKey: PhotoModel.CodingKeys._category_)
        self._displayState = try container.decode(Int.self, forKey: PhotoModel.CodingKeys._displayState)
        self._degrees_ = try container.decode(CRDT<Double>.self, forKey: PhotoModel.CodingKeys._degrees_)
        self._fileUrl_ = try container.decode(CRDTDataUpdate<FileUrl?>.self, forKey: PhotoModel.CodingKeys._fileUrl_)
        self._entries_ = try container.decode(CRDTDataUpdate<[PhotoEntryModel]>.self, forKey: PhotoModel.CodingKeys._entries_)
        self._parentId = try container.decodeIfPresent(UUID.self, forKey: PhotoModel.CodingKeys._parentId)
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
    
    public var entries: [PhotoEntryModel] {
        get { entries_.wrappedValue }
        set { entries_.wrappedValue = newValue }
    }
    var entries_: CRDTDataUpdate<[PhotoEntryModel]>

    public var parentId: UUID? = nil
    
    // only game properties
    public var players: [UUID] = []
}

extension PhotoModel: nonisolated ItemGameReportable, nonisolated ItemLinkRegistable {}

extension PhotoModel {
    var hasPhoto: Bool {
        fileUrl != nil
    }
}

extension PhotoModel: nonisolated Comparable {
    nonisolated public static func < (lhs: PhotoModel, rhs: PhotoModel) -> Bool {
        return MainActor.assumeIsolated {
            lhs.name < rhs.name
    
        }
    }
}

extension PhotoModel: nonisolated ItemDiffComparable {
    nonisolated public func merge(_ other: PhotoModel) -> PhotoModel {
        return MainActor.assumeIsolated {
            let mergedCategory = category_.merged(other: other.category_)
            let mergedEntries: CRDTDataUpdate<[PhotoEntryModel]>
            if mergedCategory.wrappedValue == .folder {
                let allIds = Set(entries.map(\.id)).union(other.entries.map(\.id))
                let combined = allIds
                    .compactMap { id in entries.first { $0.id == id } ?? other.entries.first { $0.id == id } }
                    .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
                mergedEntries = CRDTDataUpdate(wrappedValue: combined)
            } else {
                mergedEntries = entries_.merged(other: other.entries_)
            }
            return PhotoModel(
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

    nonisolated public func isSame(_ other: PhotoModel) -> Bool {
        return MainActor.assumeIsolated {
            name == other.name &&
            description == other.description &&
            tags == other.tags &&
            category == other.category &&
            degrees == other.degrees &&
            fileUrl_.update == other.fileUrl_.update &&
            entries_.update == other.entries_.update &&
            parentId == other.parentId &&
            // santity checks
            entries.count == other.entries.count &&
            entries.enumerated().allSatisfy { index, entry in
                entry == other.entries[index]
            }
    
        }
    }
    
    nonisolated public var version: Int {
        return MainActor.assumeIsolated {
            fileUrl?.contentVersion ?? fileUrl_.update.hashValue
    
        }
    }
}

extension PhotoModel: nonisolated ItemDuplicatable {
    nonisolated public func duplicate() -> PhotoModel {
        return MainActor.assumeIsolated {
            let copyName = duplicateName(from: name)
            return PhotoModel(id: UUID(), name: copyName, description: description, tags: tags, category: category, displayState: displayState, degrees: degrees, fileUrl: nil, entries: entries.map { $0.duplicate() })
    
        }
    }
}

// MARK: - Review Properties

extension PhotoModel {
    @MainActor public var reviewProperties: [ReviewCustomProperty] {
        [
            ReviewCustomProperty(displayName: "Rotation") {
                ReviewPropertyValue(($0 as? PhotoModel)?.degrees ?? 0)
            }
        ]
    }
}

extension PhotoModel: nonisolated ItemDataAccessable {
    nonisolated public static var empty: PhotoModel { empty(UUID()) }
    nonisolated public static func empty(_ id: UUID) -> PhotoModel {
        PhotoModel(id: id, name: "")
    }
    nonisolated public static let typeId: NetworkModules = .photo

    public func copy() -> PhotoModel {
        PhotoModel(id: id, name: name_, description: description_, tags: tags_, category: category_, displayState: displayState, degrees: degrees_, fileUrl: fileUrl_, entries: entries_, parentId: parentId)
    }
    
    public func filter(filter: String, includeEntries: Bool) -> Bool {
        guard !filter.isEmpty else { return true }
        guard !(name.localizedCaseInsensitiveContains(filter) || description.localizedCaseInsensitiveContains(filter)) else { return true }
        return false
    }

    public func isEqual(other: PhotoModel) -> Bool {
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

    @MainActor public func replace(with model: PhotoModel) -> Bool {
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

    public subscript(id: UUID) -> PhotoEntryModel {
        get {
            guard let index = entries.firstIndex(where: { $0.id == id }) else { return .empty(id) }
            return entries[index]
        }
        set {
            guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
            entries[index] = newValue
        }
    }

    public func urlAdr(linkNumber: Int, entryId: UUID) -> String {
        "\(URL.appScheme)://\(Self.typeId.token)/\(linkNumber)/\(entryId)"
    }

    public func urlName(entryId: UUID) -> String {
        let title = entries.first(where: { $0.id == entryId })?.name ?? name
        return "\(title.withoutLink())"
    }
}

extension PhotoModel: nonisolated Codable {
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

    nonisolated final public func encode(to encoder: Encoder) throws {
        nonisolated(unsafe) let encoder = encoder
        try MainActor.assumeIsolated {
            var container: KeyedEncodingContainer<PhotoModel.CodingKeys> = encoder.container(keyedBy: PhotoModel.CodingKeys.self)

            try container.encode(self.id, forKey: PhotoModel.CodingKeys._id)
            try container.encode(self._name_, forKey: PhotoModel.CodingKeys._name_)
            try container.encode(self._description_, forKey: PhotoModel.CodingKeys._description_)
            try container.encode(self._tags_, forKey: PhotoModel.CodingKeys._tags_)
            try container.encode(self._category_, forKey: PhotoModel.CodingKeys._category_)
            try container.encode(self._displayState, forKey: PhotoModel.CodingKeys._displayState)
            try container.encode(self._degrees_, forKey: PhotoModel.CodingKeys._degrees_)
            try container.encode(self._fileUrl_, forKey: PhotoModel.CodingKeys._fileUrl_)
            try container.encode(self._entries_, forKey: PhotoModel.CodingKeys._entries_)
            try container.encodeIfPresent(self._parentId, forKey: PhotoModel.CodingKeys._parentId)
    
        }
    }
}

extension PhotoModel: nonisolated Equatable, nonisolated Hashable {
    nonisolated public static func == (lhs: PhotoModel, rhs: PhotoModel) -> Bool {
        return MainActor.assumeIsolated {
            lhs.id == rhs.id && lhs.isSame(rhs) && lhs.displayState == rhs.displayState
    
        }
    }

    nonisolated public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
