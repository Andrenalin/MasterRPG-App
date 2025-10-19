// @copyright André Trettin

import AndrenalinKit
import Foundation
import Observation

@Observable
public final class ValueModel: Identifiable, @unchecked Sendable {
    public init(id: UUID, name: String, description: String = "", tags: [String] = [], category: ItemListCategory = .character, displayState: Int = 0, photoId: UUID? = nil, photos: [UUID] = [], entries: [ValueEntryModel] = []) {
        self.id = id
        name_ = CRDT(wrappedValue: name)
        description_ = CRDT(wrappedValue: description)
        tags_ = CRDT(wrappedValue: tags)
        category_ = CRDT(wrappedValue: category)
        self.displayState = displayState
        photoId_ = CRDT(wrappedValue: photoId)
        photos_ = CRDTDataUpdate(wrappedValue: photos)
        entries_ = CRDTDataUpdate(wrappedValue: entries)
    }

    public init(id: UUID, name: CRDT<String>, description: CRDT<String>, tags: CRDT<[String]>, category: CRDT<ItemListCategory>, displayState: Int = 0, photoId: CRDT<UUID?>, photos: CRDTDataUpdate<[UUID]>, entries: CRDTDataUpdate<[ValueEntryModel]>, parentId: UUID?) {
        self.id = id
        name_ = name
        description_ = description
        tags_ = tags
        category_ = category
        self.displayState = displayState
        photoId_ = photoId
        photos_ = photos
        entries_ = entries
        self.parentId = parentId
    }

    public init(from decoder: Decoder) throws {
        let container: KeyedDecodingContainer<ValueModel.CodingKeys> = try decoder.container(keyedBy: ValueModel.CodingKeys.self)

        self._id = try container.decode(UUID.self, forKey: ValueModel.CodingKeys._id)
        self._name_ = try container.decode(CRDT<String>.self, forKey: ValueModel.CodingKeys._name_)
        self._description_ = try container.decode(CRDT<String>.self, forKey: ValueModel.CodingKeys._description_)
        self._tags_ = try container.decode(CRDT<[String]>.self, forKey: ValueModel.CodingKeys._tags_)
        self._category_ = try container.decode(CRDT<ItemListCategory>.self, forKey: ValueModel.CodingKeys._category_)
        self._displayState = try container.decode(Int.self, forKey: ValueModel.CodingKeys._displayState)
        self._photoId_ = try container.decode(CRDT<UUID?>.self, forKey: ValueModel.CodingKeys._photoId_)
        self._photos_ = try container.decode(CRDTDataUpdate<[UUID]>.self, forKey: ValueModel.CodingKeys._photos_)
        self._entries_ = try container.decode(CRDTDataUpdate<[ValueEntryModel]>.self, forKey: ValueModel.CodingKeys._entries_)
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
    public var description_: CRDT<String>

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

    public var photos: [UUID] {
        get { photos_.wrappedValue }
        set { photos_.wrappedValue = newValue }
    }
    var photos_: CRDTDataUpdate<[UUID]>

    public var entries: [ValueEntryModel] {
        get { entries_.wrappedValue }
        set { entries_.wrappedValue = newValue }
    }
    var entries_: CRDTDataUpdate<[ValueEntryModel]>
    
    public var parentId: UUID?
    public var quickEditEntries: Set<UUID> = []
}

extension ValueModel: Comparable {
    public static func < (lhs: ValueModel, rhs: ValueModel) -> Bool {
        lhs.name < rhs.name
    }
}

extension ValueModel: ItemLinkRegistable {
    @MainActor
    public var linkRegisterModels: [LinkRegisterModel] {
        let modelSource = ItemRowModel(itemId: id, typeId: .value)
        let linkModels = photos.map {
            LinkRegisterModel(source: modelSource, destination: ItemRowModel(itemId: $0, typeId: .photo))
        }
        let entryModels = entries.reduce([]) { total, entry -> [LinkRegisterModel] in
            let source = ItemRowModel(itemId: id, entryId: entry.id, typeId: .value)
            let nameModels = entry.links(for: entry.name).map {
                LinkRegisterModel(source: source, destination: ItemRowModel(itemId: $0.itemId, entryId: $0.entryId, typeId: $0.module))
            }
            let valueModels = entry.links(for: entry.value).map {
                LinkRegisterModel(source: source, destination: ItemRowModel(itemId: $0.itemId, entryId: $0.entryId, typeId: $0.module))
            }
            var newTotal = total
            newTotal.append(contentsOf: nameModels)
            newTotal.append(contentsOf: valueModels)
            return newTotal
        }
        return linkModels + entryModels
    }
}

extension ValueModel: ItemDiffComparable {
    public func merge(_ other: ValueModel) -> ValueModel {
        ValueModel(
            id: id,
            name: name_.merged(other: other.name_),
            description: description_.merged(other: other.description_),
            tags: tags_.merged(other: other.tags_),
            category: category_.merged(other: other.category_),
            displayState: other.displayState,
            photoId: photoId_.merged(other: other.photoId_),
            photos: photos_.merged(other: other.photos_),
            entries: entries_.merged(other: other.entries_),
            parentId: other.parentId
        )
    }

    public func isSame(_ other: ValueModel) -> Bool {
        name == other.name &&
        description == other.description &&
        tags == other.tags &&
        category == other.category &&
        photoId == other.photoId &&
        photos_.update == other.photos_.update &&
        entries_.update == other.entries_.update &&
        parentId == other.parentId &&
        // santity checks
        entries.count == other.entries.count &&
        entries.enumerated().allSatisfy { index, entry in
            entry == other.entries[index]
        }
    }
}

extension ValueModel: ItemDuplicatable {
    public func duplicate() -> ValueModel {
        let copyName = duplicateName(from: name)
        return ValueModel(id: UUID(), name: copyName, description: description, tags: tags, category: category, displayState: displayState, photoId: photoId, photos: photos, entries: entries.map { $0.duplicate() })
    }

    public func duplicateWithoutCopy() -> ValueModel {
        ValueModel(id: UUID(), name: name, description: description, tags: tags, category: category, displayState: displayState, photoId: photoId, photos: photos, entries: entries.map { $0.duplicate() })
    }

    public func duplicateSubValueIds() -> [UUID] {
        entries.compactMap { $0.valueId }
    }
}

extension ValueModel: ItemReferencable {}

extension ValueModel: ItemDataAccessable {
    public var fileUrl: FileUrl? {
        get { nil }
        set(newValue) {}
    }

    public static var empty: ValueModel { empty(UUID()) }
    public static func empty(_ id: UUID) -> ValueModel {
        ValueModel(id: id, name: "", description: "", tags: [], category: .item, displayState: 0, entries: [])
    }
    public static let typeId: NetworkModules = .value

    public func copy() -> ValueModel {
        ValueModel(id: id, name: name_, description: description_, tags: tags_, category: category_, displayState: displayState, photoId: photoId_, photos: photos_, entries: entries_, parentId: parentId)
    }

    public func filter(_ filter: String) -> Bool {
        (filter.isEmpty || name.localizedCaseInsensitiveContains(filter) || description.localizedCaseInsensitiveContains(filter))
    }

    public func isEqual(other: ValueModel) -> Bool {
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

    public func replace(with model: ValueModel) -> Bool {
        guard self != model else { return false }
        name_ <=> model.name_
        description_ <=> model.description_
        tags_ <=> model.tags_
        category_ <=> model.category_
        displayState <=> model.displayState
        photoId_ <=> model.photoId_
        photos_ <=> model.photos_
        entries_ <=> model.entries_
        parentId <=> model.parentId
        return true
    }

    public subscript(id: UUID) -> ValueEntryModel {
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

extension ValueModel: Codable {
    enum CodingKeys: CodingKey {
        case _id
        case _name_
        case _description_
        case _tags_
        case _category_
        case _displayState
        case _photoId_
        case _photos_
        case _entries_
        case _parentId
    }

    public final func encode(to encoder: Encoder) throws {
        var container: KeyedEncodingContainer<ValueModel.CodingKeys> = encoder.container(keyedBy: ValueModel.CodingKeys.self)

        try container.encode(self._id, forKey: ValueModel.CodingKeys._id)
        try container.encode(self._name_, forKey: ValueModel.CodingKeys._name_)
        try container.encode(self._description_, forKey: ValueModel.CodingKeys._description_)
        try container.encode(self._tags_, forKey: ValueModel.CodingKeys._tags_)
        try container.encode(self._category_, forKey: ValueModel.CodingKeys._category_)
        try container.encode(self._displayState, forKey: ValueModel.CodingKeys._displayState)
        try container.encode(self._photoId_, forKey: ValueModel.CodingKeys._photoId_)
        try container.encode(self._photos_, forKey: ValueModel.CodingKeys._photos_)
        try container.encode(self._entries_, forKey: ValueModel.CodingKeys._entries_)
        try container.encode(self._parentId, forKey: ValueModel.CodingKeys._parentId)
    }
}

extension ValueModel: Equatable, Hashable {
    public static func == (lhs: ValueModel, rhs: ValueModel) -> Bool {
        lhs.id == rhs.id && lhs.isSame(rhs) && lhs.displayState == rhs.displayState
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
