// @copyright André Trettin

import CoreRPG
import Foundation
import Observation

@Observable
public final class PhotoModel: Identifiable, @unchecked Sendable {
    init(id: UUID, name: String, description: String = "", tags: [String] = [], category: ItemListCategory = .adventure, displayState: Int = 0, degrees: Double = 0, fileUrl: FileUrl? = nil, entries: [PhotoEntryModel] = [], parentId: UUID? = nil) {
        self.id = id
        name_ = CRDT(wrappedValue: name)
        description_ = CRDT(wrappedValue: description)
        tags_ = CRDT(wrappedValue: tags)
        category_ = CRDT(wrappedValue: category)
        self.displayState = displayState
        degrees_ = CRDT(wrappedValue: degrees)
        fileUrl_ = CRDTDataUpdate(wrappedValue: fileUrl)
        entries_ = CRDTDataUpdate(wrappedValue: entries)
        self.parentId = parentId
    }

    init(id: UUID, name: CRDT<String>, description: CRDT<String>, tags: CRDT<[String]>, category: CRDT<ItemListCategory>, displayState: Int = 0, degrees: CRDT<Double>, fileUrl: CRDTDataUpdate<FileUrl?>, entries: CRDTDataUpdate<[PhotoEntryModel]>, parentId: UUID?) {
        self.id = id
        name_ = name
        description_ = description
        tags_ = tags
        category_ = category
        self.displayState = displayState
        degrees_ = degrees
        fileUrl_ = fileUrl
        entries_ = entries
        self.parentId = parentId
    }

    public init(from decoder: Decoder) throws {
        let container: KeyedDecodingContainer<PhotoModel.CodingKeys> = try decoder.container(keyedBy: PhotoModel.CodingKeys.self)

        self._id = try container.decode(UUID.self, forKey: PhotoModel.CodingKeys._id)
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

    public var parentId: UUID? = nil
    
    // only game properties
    public var players: [UUID] = []
}

extension PhotoModel: ItemGameReportable, ItemLinkRegistable {}

extension PhotoModel {
    var hasPhoto: Bool {
        fileUrl != nil
    }
}

extension PhotoModel: Comparable {
    public static func < (lhs: PhotoModel, rhs: PhotoModel) -> Bool {
        lhs.name < rhs.name
    }
}

extension PhotoModel: ItemDiffComparable {
    public func merge(_ other: PhotoModel) -> PhotoModel {
        PhotoModel(
            id: id,
            name: name_.merged(other: other.name_),
            description: description_.merged(other: other.description_),
            tags: tags_.merged(other: other.tags_),
            category: category_.merged(other: other.category_),
            displayState: other.displayState,
            degrees: degrees_.merged(other: other.degrees_),
            fileUrl: fileUrl_.merged(other: other.fileUrl_),
            entries: entries_.merged(other: other.entries_),
            parentId: other.parentId
        )
    }

    public func isSame(_ other: PhotoModel) -> Bool {
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
    
    public var version: Int {
        fileUrl_.update.hashValue
    }
}

extension PhotoModel: ItemDuplicatable {
    public func duplicate() -> PhotoModel {
        let copyName = duplicateName(from: name)
        return PhotoModel(id: UUID(), name: copyName, description: description, tags: tags, category: category, displayState: displayState, degrees: degrees, fileUrl: nil, entries: entries.map { $0.duplicate() })
    }
}

extension PhotoModel: ItemDataAccessable {
    public static var empty: PhotoModel { empty(UUID()) }
    public static func empty(_ id: UUID) -> PhotoModel {
        PhotoModel(id: id, name: "")
    }
    public static let typeId: NetworkModules = .photo

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
        case _parentId
    }

    final public func encode(to encoder: Encoder) throws {
        var container: KeyedEncodingContainer<PhotoModel.CodingKeys> = encoder.container(keyedBy: PhotoModel.CodingKeys.self)

        try container.encode(self._id, forKey: PhotoModel.CodingKeys._id)
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

extension PhotoModel: Equatable, Hashable {
    public static func == (lhs: PhotoModel, rhs: PhotoModel) -> Bool {
        lhs.id == rhs.id && lhs.isSame(rhs) && lhs.displayState == rhs.displayState
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
