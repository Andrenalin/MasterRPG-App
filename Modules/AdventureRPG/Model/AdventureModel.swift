// @copyright André Trettin

import CoreRPG
import Foundation
import Observation

// MainActor-owned model. Sendable via global-actor isolation (no @unchecked):
// persistence crosses the Core Data boundary as AdventureSnapshot,
// the .gmz wire format stays on this type's Codable (encode/decode on MainActor).
@MainActor @Observable
public final class AdventureModel: nonisolated Identifiable {
    nonisolated init(id: UUID, name: String, description: String = "", tags: [String] = [], category: ItemListCategory = .adventure, displayState: Int = 0, photoId: UUID? = nil, diceId: UUID? = nil, entries: [AdventureEntryModel] = [], parentId: UUID? = nil, groupId: UUID? = nil) {
        self.id = id
        _name_ = CRDT(wrappedValue: name)
        _description_ = CRDT(wrappedValue: description)
        _tags_ = CRDT(wrappedValue: tags)
        _category_ = CRDT(wrappedValue: category)
        self._displayState = displayState
        _photoId_ = CRDT(wrappedValue: photoId)
        self._diceId = diceId
        _entries_ = CRDTDataUpdate(wrappedValue: entries)
        self._parentId = parentId
        self._groupId = groupId
    }

    nonisolated public init(id: UUID, name: CRDT<String>, description: CRDT<String>, tags: CRDT<[String]>, category: CRDT<ItemListCategory>, displayState: Int = 0, photoId: CRDT<UUID?>, diceId: UUID?, entries: CRDTDataUpdate<[AdventureEntryModel]>, parentId: UUID?, groupId: UUID? = nil) {
        self.id = id
        _name_ = name
        _description_ = description
        _tags_ = tags
        _category_ = category
        self._displayState = displayState
        _photoId_ = photoId
        self._diceId = diceId
        _entries_ = entries
        self._parentId = parentId
        self._groupId = groupId
    }

    nonisolated public init(from decoder: Decoder) throws {
        let container: KeyedDecodingContainer<AdventureModel.CodingKeys> = try decoder.container(keyedBy: AdventureModel.CodingKeys.self)

        self.id = try container.decode(UUID.self, forKey: AdventureModel.CodingKeys._id)
        self._name_ = try container.decode(CRDT<String>.self, forKey: AdventureModel.CodingKeys._name_)
        self._description_ = try container.decode(CRDT<String>.self, forKey: AdventureModel.CodingKeys._description_)
        self._tags_ = try container.decode(CRDT<[String]>.self, forKey: AdventureModel.CodingKeys._tags_)
        self._category_ = try container.decode(CRDT<ItemListCategory>.self, forKey: AdventureModel.CodingKeys._category_)
        self._displayState = try container.decode(Int.self, forKey: AdventureModel.CodingKeys._displayState)
        self._photoId_ = try container.decode(CRDT<UUID?>.self, forKey: AdventureModel.CodingKeys._photoId_)
        self._diceId = try container.decodeIfPresent(UUID.self, forKey: AdventureModel.CodingKeys._diceId)
        self._entries_ = try container.decode(CRDTDataUpdate<[AdventureEntryModel]>.self, forKey: AdventureModel.CodingKeys._entries_)
        self._parentId = try container.decodeIfPresent(UUID.self, forKey: AdventureModel.CodingKeys._parentId)
        self._groupId = try container.decodeIfPresent(UUID.self, forKey: AdventureModel.CodingKeys._groupId)
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

    public var photoId: UUID? {
        get { photoId_.wrappedValue }
        set { photoId_.wrappedValue = newValue }
    }
    var photoId_: CRDT<UUID?>
    
    public var diceId: UUID?

    public var entries: [AdventureEntryModel] {
        get { entries_.wrappedValue }
        set { entries_.wrappedValue = newValue }
    }
    var entries_: CRDTDataUpdate<[AdventureEntryModel]>
    
    public var parentId: UUID? = nil
    public var groupId: UUID?
}

extension AdventureModel: nonisolated ItemLinkRegistrable {
    @MainActor public var linkRegisterModels: [LinkRegisterModel] {
        changedLinkRegisterModels(oldValue: .empty).0
    }

    @MainActor public func changedLinkRegisterModels(oldValue: AdventureModel) -> (added: [LinkRegisterModel], removed: [LinkRegisterModel]) {
        var added: [LinkRegisterModel] = []
        var removed: [LinkRegisterModel] = []
        
        if oldValue.photoId != photoId {
            let modelSource = ItemRowModel(itemId: id, typeId: .adventure)
            if let photoId {
                added.append(LinkRegisterModel(name: "", source: modelSource, destination: ItemRowModel(itemId: photoId, typeId: .photo)))
            }
            if let oldPhotoId = oldValue.photoId {
                removed.append(LinkRegisterModel(name: "", source: modelSource, destination: ItemRowModel(itemId: oldPhotoId, typeId: .photo)))
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
        
    @MainActor func linkRegisterModels(entry: AdventureEntryModel, valueChanged: Bool = true) -> [LinkRegisterModel] {
        let source = ItemRowModel(itemId: id, entryId: entry.id, typeId: .adventure)
        var total: [LinkRegisterModel] = []
        if valueChanged {
            total += LinkReplaceController.links(for: entry.content).map {
                LinkRegisterModel(link: $0, source: source)
            }
        }
        return total
    }
}

extension AdventureModel: nonisolated ItemDiffComparable {
    /// Folders used to merge `entries` as a union of both sides' child ids instead of the
    /// whole-array last-write-wins used by every other property here (and by every other
    /// category's entries) — with no tombstone for removed children, that union silently
    /// resurrected a deletion made offline on one device once the next CloudKit merge ran.
    /// Uses the same whole-array LWW as everything else instead: the tradeoff is that two
    /// devices concurrently adding *different* children to the same folder while offline
    /// will have one side's addition lost rather than both being kept — preferred over
    /// silently undoing a user's explicit deletion. See CODE_AUDIT §5.3.
    nonisolated public func merge(_ other: AdventureModel) -> AdventureModel {
        return assumeMainActorIsolated {
            let mergedCategory = category_.merged(other: other.category_)
            return AdventureModel(
                id: id,
                name: name_.merged(other: other.name_),
                description: description_.merged(other: other.description_),
                tags: tags_.merged(other: other.tags_),
                category: mergedCategory,
                displayState: other.displayState,
                photoId: photoId_.merged(other: other.photoId_),
                diceId: other.diceId,
                entries: entries_.merged(other: other.entries_),
                parentId: other.parentId,
                groupId: other.groupId
            )

        }
    }

    nonisolated public func isSame(_ other: AdventureModel) -> Bool {
        return assumeMainActorIsolated {
            name == other.name &&
            description == other.description &&
            tags == other.tags &&
            category == other.category &&
            photoId == other.photoId &&
            diceId == other.diceId &&
            entries_.update == other.entries_.update &&
            parentId == other.parentId &&
            groupId == other.groupId &&
            // sanity checks
            entries.count == other.entries.count &&
            entries.enumerated().allSatisfy { index, entry in
                entry == other.entries[index]
            }
    
        }
    }
}

// MARK: - Review Properties

extension AdventureModel {
    @MainActor public var reviewProperties: [ReviewCustomProperty] {
        [
            ReviewCustomProperty(displayName: String(localized: "Photo", bundle: .module)) { ReviewPropertyValue(photoId: ($0 as? AdventureModel)?.photoId) },
            ReviewCustomProperty(displayName: String(localized: "Dice", bundle: .module)) { ReviewPropertyValue(diceId: ($0 as? AdventureModel)?.diceId) }
        ]
    }
}

extension AdventureModel: nonisolated ItemDuplicatable {
    nonisolated public func duplicate() -> AdventureModel {
        return assumeMainActorIsolated {
            let copyName = duplicateName(from: name)
            // Carries `diceId` too. See CODE_AUDIT_Folder §5.27.
            return AdventureModel(id: UUID(), name: copyName, description: description, tags: tags, category: category, displayState: displayState, photoId: photoId, diceId: diceId, entries: entries.map { $0.duplicate() }, parentId: nil, groupId: nil)
    
        }
    }

    nonisolated func duplicateWithoutCopy() -> AdventureModel {
        return assumeMainActorIsolated {
            AdventureModel(id: UUID(), name: name, description: description, tags: tags, category: category, displayState: displayState, photoId: photoId, diceId: diceId, entries: entries.map { $0.duplicate() }, parentId: parentId, groupId: groupId)
        }
    }
}


extension AdventureModel: nonisolated ItemDataAccessible {
    public var fileUrl: FileUrl? {
        get { nil }
        set(newValue) {}
    }

    nonisolated public static var empty: AdventureModel { empty(UUID()) }
    nonisolated public static func empty(_ id: UUID) -> AdventureModel {
        AdventureModel(id: id, name: "", description: "")
    }
    nonisolated public static let typeId: NetworkModules = .adventure

    public func copy() -> AdventureModel {
        AdventureModel(id: id, name: name_, description: description_, tags: tags_, category: category_, displayState: displayState, photoId: photoId_, diceId: diceId, entries: entries_, parentId: parentId, groupId: groupId)
    }

    public func filter(filter: String, includeEntries: Bool) -> Bool {
        guard !filter.isEmpty else { return true }
        guard !(name.localizedStandardContains(filter) || description.localizedStandardContains(filter)) else { return true }
        guard specialCategory == false else { return false }
        return entries.contains {
            $0.filter(with: filter)
        }
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

    @MainActor public func replace(with model: AdventureModel) -> Bool {
        guard self != model else { return false }
        name_ <=> model.name_
        description_ <=> model.description_
        tags_ <=> model.tags_
        category_ <=> model.category_
        displayState <=> model.displayState
        photoId_ <=> model.photoId_
        diceId <=> model.diceId
        entries_ <=> model.entries_
        parentId <=> model.parentId
        groupId <=> model.groupId
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

// See CODE_AUDIT_EditItem §9.5 — lets `EditController`'s orphan-handling trio
// (`isOrphanedHidden`/`willRepairOrphan`/`willRestore`) use the shared
// `GroupableModel`-constrained default in `EditControllable` instead of its own copy.
extension AdventureModel: nonisolated GroupableModel {}

extension AdventureModel: nonisolated Comparable {
    nonisolated public static func < (lhs: AdventureModel, rhs: AdventureModel) -> Bool {
        return assumeMainActorIsolated {
            lhs.name < rhs.name
    
        }
    }
}

extension AdventureModel: nonisolated Codable {
    enum CodingKeys: CodingKey {
        case _id
        case _name_
        case _description_
        case _tags_
        case _category_
        case _displayState
        case _photoId_
        case _diceId
        case _entries_
        case _parentId
        case _groupId
    }

    nonisolated public final func encode(to encoder: Encoder) throws {
        try encoder.encodeOnMainActor { encoder in
            var container: KeyedEncodingContainer<AdventureModel.CodingKeys> = encoder.container(keyedBy: AdventureModel.CodingKeys.self)

            try container.encode(self.id, forKey: AdventureModel.CodingKeys._id)
            try container.encode(self._name_, forKey: AdventureModel.CodingKeys._name_)
            try container.encode(self._description_, forKey: AdventureModel.CodingKeys._description_)
            try container.encode(self._tags_, forKey: AdventureModel.CodingKeys._tags_)
            try container.encode(self._category_, forKey: AdventureModel.CodingKeys._category_)
            try container.encode(self._displayState, forKey: AdventureModel.CodingKeys._displayState)
            try container.encode(self._photoId_, forKey: AdventureModel.CodingKeys._photoId_)
            try container.encodeIfPresent(self._diceId, forKey: AdventureModel.CodingKeys._diceId)
            try container.encode(self._entries_, forKey: AdventureModel.CodingKeys._entries_)
            try container.encodeIfPresent(self._parentId, forKey: AdventureModel.CodingKeys._parentId)
            try container.encodeIfPresent(self._groupId, forKey: AdventureModel.CodingKeys._groupId)
    
        }
    }
}

extension AdventureModel: nonisolated Equatable, nonisolated Hashable {
    nonisolated public static func == (lhs: AdventureModel, rhs: AdventureModel) -> Bool {
        return assumeMainActorIsolated {
            lhs.id == rhs.id && lhs.isSame(rhs) && lhs.displayState == rhs.displayState
    
        }
    }

    nonisolated public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
