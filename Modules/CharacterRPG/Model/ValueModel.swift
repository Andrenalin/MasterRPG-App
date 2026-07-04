// @copyright André Trettin

import CoreRPG
import Foundation
import Observation

// MainActor-owned model. Sendable via global-actor isolation (no @unchecked):
// persistence crosses the Core Data boundary as ValueSnapshot,
// the .gmz wire format stays on this type's Codable (encode/decode on MainActor).
@MainActor @Observable
public final class ValueModel: nonisolated Identifiable {
    nonisolated public init(id: UUID, name: String, description: String = "", tags: [String] = [], category: ItemListCategory = .character, displayState: Int = 0, photoId: UUID? = nil, photos: [UUID] = [], entries: [ValueEntryModel] = [], parentId: UUID? = nil, diceId: UUID? = nil, groupId: UUID? = nil) {
        self.id = id
        _name_ = CRDT(wrappedValue: name)
        _description_ = CRDT(wrappedValue: description)
        _tags_ = CRDT(wrappedValue: tags)
        _category_ = CRDT(wrappedValue: category)
        self._displayState = displayState
        _photoId_ = CRDT(wrappedValue: photoId)
        _photos_ = CRDTDataUpdate(wrappedValue: photos)
        _entries_ = CRDTDataUpdate(wrappedValue: entries)
        self._parentId = parentId
        self._diceId = diceId
        self._groupId = groupId
    }

    nonisolated public init(id: UUID, name: CRDT<String>, description: CRDT<String>, tags: CRDT<[String]>, category: CRDT<ItemListCategory>, displayState: Int = 0, photoId: CRDT<UUID?>, photos: CRDTDataUpdate<[UUID]>, entries: CRDTDataUpdate<[ValueEntryModel]>, parentId: UUID?, diceId: UUID?, groupId: UUID? = nil) {
        self.id = id
        _name_ = name
        _description_ = description
        _tags_ = tags
        _category_ = category
        self._displayState = displayState
        _photoId_ = photoId
        _photos_ = photos
        _entries_ = entries
        self._parentId = parentId
        self._diceId = diceId
        self._groupId = groupId
    }

    nonisolated public init(from decoder: Decoder) throws {
        let container: KeyedDecodingContainer<ValueModel.CodingKeys> = try decoder.container(keyedBy: ValueModel.CodingKeys.self)

        self.id = try container.decode(UUID.self, forKey: ValueModel.CodingKeys._id)
        self._name_ = try container.decode(CRDT<String>.self, forKey: ValueModel.CodingKeys._name_)
        self._description_ = try container.decode(CRDT<String>.self, forKey: ValueModel.CodingKeys._description_)
        self._tags_ = try container.decode(CRDT<[String]>.self, forKey: ValueModel.CodingKeys._tags_)
        self._category_ = try container.decode(CRDT<ItemListCategory>.self, forKey: ValueModel.CodingKeys._category_)
        let decodedDisplayState = try container.decode(Int.self, forKey: ValueModel.CodingKeys._displayState)
        self._displayState = decodedDisplayState
        self._photoId_ = try container.decode(CRDT<UUID?>.self, forKey: ValueModel.CodingKeys._photoId_)
        self._photos_ = try container.decode(CRDTDataUpdate<[UUID]>.self, forKey: ValueModel.CodingKeys._photos_)
        self._entries_ = try container.decode(CRDTDataUpdate<[ValueEntryModel]>.self, forKey: ValueModel.CodingKeys._entries_)
        let decodedParentId = try container.decodeIfPresent(UUID.self, forKey: ValueModel.CodingKeys._parentId)
        self._diceId = try container.decodeIfPresent(UUID.self, forKey: ValueModel.CodingKeys._diceId)
        let decodedGroupId = try container.decodeIfPresent(UUID.self, forKey: ValueModel.CodingKeys._groupId)
        // Migrate pre-groupId data: items with displayState==1 used parentId for group membership
        if decodedGroupId == nil && decodedDisplayState == 1, let parentId = decodedParentId {
            self._parentId = nil
            self._groupId = parentId
        } else {
            self._parentId = decodedParentId
            self._groupId = decodedGroupId
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
    public var diceId: UUID?
    public var groupId: UUID?
    
    public var quickEditEntries: Set<UUID> = []
}

extension ValueModel: nonisolated Comparable {
    nonisolated public static func < (lhs: ValueModel, rhs: ValueModel) -> Bool {
        return MainActor.assumeIsolated {
            lhs.name < rhs.name
    
        }
    }
}

extension ValueModel: nonisolated ItemLinkRegistable {
    @MainActor public var linkRegisterModels: [LinkRegisterModel] {
        changedLinkRegisterModels(oldValue: .empty).0
    }
    
    @MainActor public func changedLinkRegisterModels(oldValue: ValueModel) -> (added: [LinkRegisterModel], removed: [LinkRegisterModel]) {
        var added: [LinkRegisterModel] = []
        var removed: [LinkRegisterModel] = []
        
        if oldValue.photos != photos {
            let modelSource = ItemRowModel(itemId: id, typeId: .value)
            let addedPhotos = Set(photos).subtracting(Set(oldValue.photos))
            let removedPhotos = Set(oldValue.photos).subtracting(Set(photos))
            addedPhotos.forEach {
                added.append(LinkRegisterModel(name: "", source: modelSource, destination: ItemRowModel(itemId: $0, typeId: .photo)))
            }
            removedPhotos.forEach {
                removed.append(LinkRegisterModel(name: "", source: modelSource, destination: ItemRowModel(itemId: $0, typeId: .photo)))
            }
        }

        if oldValue.diceId != diceId {
            let modelSource = ItemRowModel(itemId: id, typeId: .value)
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
                    removed.append(contentsOf: linkRegisterModels(entry: oldEntry, nameChanged: oldEntry.name != newEntry.name, valueChanged: oldEntry.value != newEntry.value))
                    added.append(contentsOf: linkRegisterModels(entry: oldEntry, nameChanged: oldEntry.name != newEntry.name, valueChanged: oldEntry.value != newEntry.value))
                }
            }
        }
        
        return (added, removed)
    }
        
    @MainActor func linkRegisterModels(entry: ValueEntryModel, nameChanged: Bool = true, valueChanged: Bool = true) -> [LinkRegisterModel] {
        let source = ItemRowModel(itemId: id, entryId: entry.id, typeId: .value)
        var total: [LinkRegisterModel] = []
        if nameChanged {
            total += entry.links(for: entry.name).map {
                LinkRegisterModel(name: $0.name, source: source, destination: ItemRowModel(itemId: $0.itemId, entryId: $0.entryId, typeId: $0.module), markDown: $0.markDown)
            }
        }
        if valueChanged {
            total += entry.links(for: entry.value).map {
                LinkRegisterModel(name: $0.name, source: source, destination: ItemRowModel(itemId: $0.itemId, entryId: $0.entryId, typeId: $0.module), markDown: $0.markDown)
            }
        }
        return total
    }
}

extension ValueModel: nonisolated ItemDiffComparable {
    nonisolated public func merge(_ other: ValueModel) -> ValueModel {
        return MainActor.assumeIsolated {
            let mergedCategory = category_.merged(other: other.category_)
            let mergedEntries: CRDTDataUpdate<[ValueEntryModel]>
            if mergedCategory.wrappedValue == .folder {
                let allIds = Set(entries.map(\.id)).union(other.entries.map(\.id))
                let combined = allIds
                    .compactMap { id in entries.first { $0.id == id } ?? other.entries.first { $0.id == id } }
                    .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
                mergedEntries = CRDTDataUpdate(wrappedValue: combined)
            } else {
                mergedEntries = entries_.merged(other: other.entries_)
            }
            return ValueModel(
                id: id,
                name: name_.merged(other: other.name_),
                description: description_.merged(other: other.description_),
                tags: tags_.merged(other: other.tags_),
                category: mergedCategory,
                displayState: other.displayState,
                photoId: photoId_.merged(other: other.photoId_),
                photos: photos_.merged(other: other.photos_),
                entries: mergedEntries,
                parentId: other.parentId,
                diceId: other.diceId,
                groupId: other.groupId
            )
    
        }
    }

    nonisolated public func isSame(_ other: ValueModel) -> Bool {
        return MainActor.assumeIsolated {
            name == other.name &&
            description == other.description &&
            tags == other.tags &&
            category == other.category &&
            photoId == other.photoId &&
            photos_.update == other.photos_.update &&
            entries_.update == other.entries_.update &&
            parentId == other.parentId &&
            diceId == other.diceId &&
            groupId == other.groupId &&
            // santity checks
            entries.count == other.entries.count &&
            entries.enumerated().allSatisfy { index, entry in
                entry == other.entries[index]
            }
    
        }
    }
}

// MARK: - Review Properties

extension ValueModel {
    @MainActor public var reviewProperties: [ReviewCustomProperty] {
        [
            ReviewCustomProperty(displayName: "Photo") { ReviewPropertyValue(photoId: ($0 as? ValueModel)?.photoId) },
            ReviewCustomProperty(displayName: "Dice") { ReviewPropertyValue(diceId: ($0 as? ValueModel)?.diceId) },
            ReviewCustomProperty(displayName: "Photos") { ReviewPropertyValue(($0 as? ValueModel)?.photos.count ?? 0) }
        ]
    }
}

extension ValueModel: nonisolated ItemDuplicatable {
    nonisolated public func duplicate() -> ValueModel {
        return MainActor.assumeIsolated {
            let copyName = duplicateName(from: name)
            return ValueModel(id: UUID(), name: copyName, description: description, tags: tags, category: category, displayState: displayState, photoId: photoId, photos: photos, entries: entries.map { $0.duplicate() }, parentId: nil, diceId: diceId, groupId: nil)
    
        }
    }

    public func duplicateWithoutCopy() -> ValueModel {
        ValueModel(id: UUID(), name: name, description: description, tags: tags, category: category, displayState: displayState, photoId: photoId, photos: photos, entries: entries.map { $0.duplicate() }, parentId: parentId, diceId: diceId, groupId: groupId)
    }

    public func duplicateSubValueIds() -> [UUID] {
        entries.compactMap { $0.valueId }
    }
}

extension ValueModel: nonisolated ItemReferencable {}

extension ValueModel: nonisolated ItemDataAccessable {
    public var fileUrl: FileUrl? {
        get { nil }
        set(newValue) {}
    }

    nonisolated public static var empty: ValueModel { empty(UUID()) }
    nonisolated public static func empty(_ id: UUID) -> ValueModel {
        ValueModel(id: id, name: "", description: "", tags: [], category: .item, displayState: 0, entries: [])
    }
    nonisolated public static let typeId: NetworkModules = .value

    public func copy() -> ValueModel {
        ValueModel(id: id, name: name_, description: description_, tags: tags_, category: category_, displayState: displayState, photoId: photoId_, photos: photos_, entries: entries_, parentId: parentId, diceId: diceId, groupId: groupId)
    }

    public func filter(filter: String, includeEntries: Bool) -> Bool {
        guard !filter.isEmpty else { return true }
        guard !(name.localizedCaseInsensitiveContains(filter) || description.localizedCaseInsensitiveContains(filter)) else { return true }
        guard specialCategory == false else { return false }
        return entries.contains {
            $0.filter(with: filter)
        }
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

    @MainActor public func replace(with model: ValueModel) -> Bool {
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
        diceId <=> model.diceId
        groupId <=> model.groupId
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

extension ValueModel: nonisolated Codable {
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
        case _diceId
        case _groupId
    }

    nonisolated public final func encode(to encoder: Encoder) throws {
        nonisolated(unsafe) let encoder = encoder
        try MainActor.assumeIsolated {
            var container: KeyedEncodingContainer<ValueModel.CodingKeys> = encoder.container(keyedBy: ValueModel.CodingKeys.self)

            try container.encode(self.id, forKey: ValueModel.CodingKeys._id)
            try container.encode(self._name_, forKey: ValueModel.CodingKeys._name_)
            try container.encode(self._description_, forKey: ValueModel.CodingKeys._description_)
            try container.encode(self._tags_, forKey: ValueModel.CodingKeys._tags_)
            try container.encode(self._category_, forKey: ValueModel.CodingKeys._category_)
            try container.encode(self._displayState, forKey: ValueModel.CodingKeys._displayState)
            try container.encode(self._photoId_, forKey: ValueModel.CodingKeys._photoId_)
            try container.encode(self._photos_, forKey: ValueModel.CodingKeys._photos_)
            try container.encode(self._entries_, forKey: ValueModel.CodingKeys._entries_)
            try container.encodeIfPresent(self._parentId, forKey: ValueModel.CodingKeys._parentId)
            try container.encodeIfPresent(self._diceId, forKey: ValueModel.CodingKeys._diceId)
            try container.encodeIfPresent(self._groupId, forKey: ValueModel.CodingKeys._groupId)
    
        }
    }
}

extension ValueModel: nonisolated Equatable, nonisolated Hashable {
    nonisolated public static func == (lhs: ValueModel, rhs: ValueModel) -> Bool {
        return MainActor.assumeIsolated {
            lhs.id == rhs.id && lhs.isSame(rhs) && lhs.displayState == rhs.displayState
    
        }
    }

    nonisolated public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
