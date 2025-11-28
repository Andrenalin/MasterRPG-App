// @copyright André Trettin

import AndrenalinKit
import Foundation
import Observation

@Observable
public final class AdventureModel: Identifiable, @unchecked Sendable {
    init(id: UUID, name: String, description: String = "", tags: [String] = [], category: ItemListCategory = .adventure, displayState: Int = 0, photoId: UUID? = nil, entries: [AdventureEntryModel] = []) {
        self.id = id
        name_ = CRDT(wrappedValue: name)
        description_ = CRDT(wrappedValue: description)
        tags_ = CRDT(wrappedValue: tags)
        category_ = CRDT(wrappedValue: category)
        self.displayState = displayState
        photoId_ = CRDT(wrappedValue: photoId)
        entries_ = CRDTDataUpdate(wrappedValue: entries)
    }

    public init(id: UUID, name: CRDT<String>, description: CRDT<String>, tags: CRDT<[String]>, category: CRDT<ItemListCategory>, displayState: Int = 0, photoId: CRDT<UUID?>, entries: CRDTDataUpdate<[AdventureEntryModel]>) {
        self.id = id
        name_ = name
        description_ = description
        tags_ = tags
        category_ = category
        self.displayState = displayState
        photoId_ = photoId
        entries_ = entries
    }

    public init(from decoder: Decoder) throws {
        let container: KeyedDecodingContainer<AdventureModel.CodingKeys> = try decoder.container(keyedBy: AdventureModel.CodingKeys.self)

        self._id = try container.decode(UUID.self, forKey: AdventureModel.CodingKeys._id)
        self._name_ = try container.decode(CRDT<String>.self, forKey: AdventureModel.CodingKeys._name_)
        self._description_ = try container.decode(CRDT<String>.self, forKey: AdventureModel.CodingKeys._description_)
        self._tags_ = try container.decode(CRDT<[String]>.self, forKey: AdventureModel.CodingKeys._tags_)
        self._category_ = try container.decode(CRDT<ItemListCategory>.self, forKey: AdventureModel.CodingKeys._category_)
        self._displayState = try container.decode(Int.self, forKey: AdventureModel.CodingKeys._displayState)
        self._photoId_ = try container.decode(CRDT<UUID?>.self, forKey: AdventureModel.CodingKeys._photoId_)
        self._entries_ = try container.decode(CRDTDataUpdate<[AdventureEntryModel]>.self, forKey: AdventureModel.CodingKeys._entries_)
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

    public var photoId: UUID? {
        get { photoId_.wrappedValue }
        set { photoId_.wrappedValue = newValue }
    }
    var photoId_: CRDT<UUID?>

    public var entries: [AdventureEntryModel] {
        get { entries_.wrappedValue }
        set { entries_.wrappedValue = newValue }
    }
    var entries_: CRDTDataUpdate<[AdventureEntryModel]>
    
    public var parentId: UUID? = nil
}

extension AdventureModel: ItemLinkRegistable {
    @MainActor
    public var linkRegisterModels: [LinkRegisterModel] {
        let modelSource = ItemRowModel(itemId: id, typeId: .adventure)
        var linkModels: [LinkRegisterModel] = []
        if let photoId {
            linkModels.append(LinkRegisterModel(name: "", source: modelSource, destination: ItemRowModel(itemId: photoId, typeId: .photo)))

        }
        let entryModels = entries.reduce([]) { total, entry -> [LinkRegisterModel] in
            let source = ItemRowModel(itemId: id, entryId: entry.id, typeId: .adventure)
            let models = entry.links(for: entry.content).map {
                LinkRegisterModel(name: $0.name, source: source, destination: ItemRowModel(itemId: $0.itemId, entryId: $0.entryId, typeId: $0.module), markDown: $0.markDown)
            }
            var newTotal = total
            newTotal.append(contentsOf: models)
            return newTotal
        }
        return linkModels + entryModels
    }
}

extension AdventureModel: ItemDiffComparable {
    public func merge(_ other: AdventureModel) -> AdventureModel {
        AdventureModel(
            id: id,
            name: name_.merged(other: other.name_),
            description: description_.merged(other: other.description_),
            tags: tags_.merged(other: other.tags_),
            category: category_.merged(other: other.category_),
            displayState: other.displayState,
            photoId: photoId_.merged(other: other.photoId_),
            entries: entries_.merged(other: other.entries_)
        )
    }

    public func isSame(_ other: AdventureModel) -> Bool {
        name == other.name &&
        description == other.description &&
        tags == other.tags &&
        category == other.category &&
        photoId == other.photoId &&
        entries_.update == other.entries_.update &&
        // santity checks
        entries.count == other.entries.count &&
        entries.enumerated().allSatisfy { index, entry in
            entry == other.entries[index]
        }
    }
}

extension AdventureModel: ItemDuplicatable {
    public func duplicate() -> AdventureModel {
        let copyName = duplicateName(from: name)
        return AdventureModel(id: UUID(), name: copyName, description: description, tags: tags, category: category, displayState: displayState, photoId: photoId, entries: entries.map { $0.duplicate() })
    }
}

extension AdventureModel: ItemReferencable {}

extension AdventureModel: ItemDataAccessable {
    public var fileUrl: FileUrl? {
        get { nil }
        set(newValue) {}
    }

    public static var empty: AdventureModel { empty(UUID()) }
    public static func empty(_ id: UUID) -> AdventureModel {
        AdventureModel(id: id, name: "", description: "")
    }
    public static let typeId: NetworkModules = .adventure

    public func copy() -> AdventureModel {
        AdventureModel(id: id, name: name_, description: description_, tags: tags_, category: category_, displayState: displayState, photoId: photoId_, entries: entries_)
    }

    public func filter(_ filter: String) -> Bool {
        (filter.isEmpty || name.localizedCaseInsensitiveContains(filter) || description.localizedCaseInsensitiveContains(filter))
    }

    public func isEqual(other: AdventureModel) -> Bool {
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

    public func replace(with model: AdventureModel) -> Bool {
        guard self != model else { return false }
        name_ <=> model.name_
        description_ <=> model.description_
        tags_ <=> model.tags_
        category_ <=> model.category_
        displayState <=> model.displayState
        photoId_ <=> model.photoId_
        entries_ <=> model.entries_
        return true
    }

    public subscript(id: UUID) -> AdventureEntryModel {
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

extension AdventureModel: Comparable {
    public static func < (lhs: AdventureModel, rhs: AdventureModel) -> Bool {
        lhs.name < rhs.name
    }
}

extension AdventureModel: Codable {
    enum CodingKeys: CodingKey {
        case _id
        case _name_
        case _description_
        case _tags_
        case _category_
        case _displayState
        case _photoId_
        case _entries_
    }

    public final func encode(to encoder: Encoder) throws {
        var container: KeyedEncodingContainer<AdventureModel.CodingKeys> = encoder.container(keyedBy: AdventureModel.CodingKeys.self)

        try container.encode(self._id, forKey: AdventureModel.CodingKeys._id)
        try container.encode(self._name_, forKey: AdventureModel.CodingKeys._name_)
        try container.encode(self._description_, forKey: AdventureModel.CodingKeys._description_)
        try container.encode(self._tags_, forKey: AdventureModel.CodingKeys._tags_)
        try container.encode(self._category_, forKey: AdventureModel.CodingKeys._category_)
        try container.encode(self._displayState, forKey: AdventureModel.CodingKeys._displayState)
        try container.encode(self._photoId_, forKey: AdventureModel.CodingKeys._photoId_)
        try container.encode(self._entries_, forKey: AdventureModel.CodingKeys._entries_)
    }
}

extension AdventureModel: Equatable, Hashable {
    public static func == (lhs: AdventureModel, rhs: AdventureModel) -> Bool {
        lhs.id == rhs.id && lhs.isSame(rhs) && lhs.displayState == rhs.displayState
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
