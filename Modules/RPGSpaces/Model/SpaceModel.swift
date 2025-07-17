// @copyright André Trettin

import AndrenalinKit
import Foundation
import Observation

@Observable
public final class SpaceModel: Identifiable, @unchecked Sendable {
    init(id: UUID, name: String, description: String = "", tags: [String] = [], category: ItemListCategory = .item, displayState: Int = 0, degrees: Double = 0, fileUrl: FileUrl? = nil, entries: [SpaceEntryModel] = []) {
        self.id = id
        name_ = CRDT(wrappedValue: name)
        description_ = CRDT(wrappedValue: description)
        tags_ = CRDT(wrappedValue: tags)
        category_ = CRDT(wrappedValue: category)
        self.displayState = displayState
        degrees_ = CRDT(wrappedValue: degrees)
        fileUrl_ = CRDTDataUpdate(wrappedValue: fileUrl)
        entries_ = CRDTDataUpdate(wrappedValue: entries)
    }

    init(id: UUID, name: CRDT<String>, description: CRDT<String>, tags: CRDT<[String]>, category: CRDT<ItemListCategory>, displayState: Int = 0, degrees: CRDT<Double>, fileUrl: CRDTDataUpdate<FileUrl?>, entries: CRDTDataUpdate<[SpaceEntryModel]>) {
        self.id = id
        name_ = name
        description_ = description
        tags_ = tags
        category_ = category
        self.displayState = displayState
        degrees_ = degrees
        fileUrl_ = fileUrl
        entries_ = entries
    }

    public init(from decoder: Decoder) throws {
        let container: KeyedDecodingContainer<SpaceModel.CodingKeys> = try decoder.container(keyedBy: SpaceModel.CodingKeys.self)

        self._id = try container.decode(UUID.self, forKey: SpaceModel.CodingKeys._id)
        self._name_ = try container.decode(CRDT<String>.self, forKey: SpaceModel.CodingKeys._name_)
        self._description_ = try container.decode(CRDT<String>.self, forKey: SpaceModel.CodingKeys._description_)
        self._tags_ = try container.decode(CRDT<[String]>.self, forKey: SpaceModel.CodingKeys._tags_)
        self._category_ = try container.decode(CRDT<ItemListCategory>.self, forKey: SpaceModel.CodingKeys._category_)
        self._displayState = try container.decode(Int.self, forKey: SpaceModel.CodingKeys._displayState)
        self._degrees_ = try container.decode(CRDT<Double>.self, forKey: SpaceModel.CodingKeys._degrees_)
        self._fileUrl_ = try container.decode(CRDTDataUpdate<FileUrl?>.self, forKey: SpaceModel.CodingKeys._fileUrl_)
        self._entries_ = try container.decode(CRDTDataUpdate<[SpaceEntryModel]>.self, forKey: SpaceModel.CodingKeys._entries_)
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
    
    public var entries: [SpaceEntryModel] {
        get { entries_.wrappedValue }
        set { entries_.wrappedValue = newValue }
    }
    var entries_: CRDTDataUpdate<[SpaceEntryModel]>

    // only game properties
    public var players: [UUID] = []
}

extension SpaceModel {
    var hasSpace: Bool {
        fileUrl != nil
    }
}

extension SpaceModel: Comparable {
    public static func < (lhs: SpaceModel, rhs: SpaceModel) -> Bool {
        lhs.name < rhs.name
    }
}

extension SpaceModel: ItemGameReportable {}
extension SpaceModel: ItemLinkRegistable {}

extension SpaceModel: ItemDiffComparable {
    public func merge(_ other: SpaceModel) -> SpaceModel {
        SpaceModel(
            id: id,
            name: name_.merged(other: other.name_),
            description: description_.merged(other: other.description_),
            tags: tags_.merged(other: other.tags_),
            category: category_.merged(other: other.category_),
            displayState: other.displayState,
            degrees: degrees_.merged(other: other.degrees_),
            fileUrl: fileUrl_.merged(other: other.fileUrl_),
            entries: entries_.merged(other: other.entries_)
        )
    }

    public func isSame(_ other: SpaceModel) -> Bool {
        name == other.name &&
        description == other.description &&
        tags == other.tags &&
        category == other.category &&
        degrees == other.degrees &&
        fileUrl_.update == other.fileUrl_.update &&
        entries_.update == other.entries_.update
    }
    
    public var version: Int {
        fileUrl_.update.hashValue
    }
}

extension SpaceModel: ItemDuplicatable {
    public func duplicate() -> SpaceModel {
        let copyName = duplicateName(from: name)
        return SpaceModel(id: UUID(), name: copyName, description: description, tags: tags, category: category, displayState: displayState, degrees: degrees, fileUrl: nil, entries: entries.map { $0.duplicate() })
    }
}

extension SpaceModel: ItemDataAccessable {
    public static var empty: SpaceModel { empty(UUID()) }
    public static func empty(_ id: UUID) -> SpaceModel {
        SpaceModel(id: id, name: "")
    }
    public static let typeId: NetworkModules = .space

    public func copy() -> SpaceModel {
        SpaceModel(id: id, name: name_, description: description_, tags: tags_, category: category_, displayState: displayState, degrees: degrees_, fileUrl: fileUrl_, entries: entries_)
    }
    
    public func filter(_ filter: String) -> Bool {
        (filter.isEmpty || name.localizedCaseInsensitiveContains(filter) || description.localizedCaseInsensitiveContains(filter))
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

    public func replace(with model: SpaceModel) -> Bool {
        guard self != model else { return false }
        name_ <=> model.name_
        description_ <=> model.description_
        tags_ <=> model.tags_
        category_ <=> model.category_
        displayState <=> model.displayState
        degrees_ <=> model.degrees_
        fileUrl_ <=> model.fileUrl_
        entries_ <=> model.entries_
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

extension SpaceModel: Codable {
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
    }

    public final func encode(to encoder: Encoder) throws {
        var container: KeyedEncodingContainer<SpaceModel.CodingKeys> = encoder.container(keyedBy: SpaceModel.CodingKeys.self)

        try container.encode(self._id, forKey: SpaceModel.CodingKeys._id)
        try container.encode(self._name_, forKey: SpaceModel.CodingKeys._name_)
        try container.encode(self._description_, forKey: SpaceModel.CodingKeys._description_)
        try container.encode(self._tags_, forKey: SpaceModel.CodingKeys._tags_)
        try container.encode(self._category_, forKey: SpaceModel.CodingKeys._category_)
        try container.encode(self._displayState, forKey: SpaceModel.CodingKeys._displayState)
        try container.encode(self._degrees_, forKey: SpaceModel.CodingKeys._degrees_)
        try container.encode(self._fileUrl_, forKey: SpaceModel.CodingKeys._fileUrl_)
        try container.encode(self._entries_, forKey: SpaceModel.CodingKeys._entries_)
    }
}

extension SpaceModel: Equatable, Hashable {
    public static func == (lhs: SpaceModel, rhs: SpaceModel) -> Bool {
        lhs.id == rhs.id && lhs.isSame(rhs) && lhs.displayState == rhs.displayState
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
