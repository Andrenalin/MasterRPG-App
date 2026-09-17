// @copyright André Trettin

import CoreRPG
import Foundation
import Observation

#if canImport(PDFKit)
import PDFKit
#endif

#if canImport(QuickLookThumbnailing)
import QuickLookThumbnailing
#endif

// MainActor-owned model. Sendable via global-actor isolation (no @unchecked):
// persistence crosses the Core Data boundary as PdfSnapshot,
// the .gmz wire format stays on this type's Codable (encode/decode on MainActor).
@MainActor @Observable
public final class PdfModel: nonisolated Identifiable {
    nonisolated init(id: UUID, name: String, description: String = "", tags: [String] = [], category: ItemListCategory = .rules, displayState: Int = 0, fileUrl: FileUrl? = nil, entries: [PdfEntryModel] = [], parentId: UUID? = nil) {
        self.id = id
        _name_ = CRDT(wrappedValue: name)
        _description_ = CRDT(wrappedValue: description)
        _tags_ = CRDT(wrappedValue: tags)
        _category_ = CRDT(wrappedValue: category)
        self._displayState = displayState
        _fileUrl_ = CRDTDataUpdate(wrappedValue: fileUrl)
        _entries_ = CRDTDataUpdate(wrappedValue: entries)
        self._parentId = parentId
    }

    nonisolated init(id: UUID, name: CRDT<String>, description: CRDT<String>, tags: CRDT<[String]>, category: CRDT<ItemListCategory>, displayState: Int = 0, fileUrl: CRDTDataUpdate<FileUrl?>, entries: CRDTDataUpdate<[PdfEntryModel]>, parentId: UUID?) {
        self.id = id
        _name_ = name
        _description_ = description
        _tags_ = tags
        _category_ = category
        self._displayState = displayState
        _fileUrl_ = fileUrl
        _entries_ = entries
        self._parentId = parentId
    }

    nonisolated public init(from decoder: Decoder) throws {
        let container: KeyedDecodingContainer<PdfModel.CodingKeys> = try decoder.container(keyedBy: PdfModel.CodingKeys.self)

        self.id = try container.decode(UUID.self, forKey: PdfModel.CodingKeys._id)
        self._name_ = try container.decode(CRDT<String>.self, forKey: PdfModel.CodingKeys._name_)
        self._description_ = try container.decode(CRDT<String>.self, forKey: PdfModel.CodingKeys._description_)
        self._tags_ = try container.decode(CRDT<[String]>.self, forKey: PdfModel.CodingKeys._tags_)
        self._category_ = try container.decode(CRDT<ItemListCategory>.self, forKey: PdfModel.CodingKeys._category_)
        self._displayState = try container.decode(Int.self, forKey: PdfModel.CodingKeys._displayState)
        self._fileUrl_ = try container.decode(CRDTDataUpdate<FileUrl?>.self, forKey: PdfModel.CodingKeys._fileUrl_)
        self._entries_ = try container.decode(CRDTDataUpdate<[PdfEntryModel]>.self, forKey: PdfModel.CodingKeys._entries_)
        self._parentId = try container.decodeIfPresent(UUID.self, forKey: PdfModel.CodingKeys._parentId)
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

    public var fileUrl: FileUrl? {
        get { fileUrl_.wrappedValue }
        set { fileUrl_.wrappedValue = newValue }
    }
    public var fileUrl_: CRDTDataUpdate<FileUrl?>

    public var entries: [PdfEntryModel] {
        get { entries_.wrappedValue }
        set { entries_.wrappedValue = newValue }
    }
    public var entries_: CRDTDataUpdate<[PdfEntryModel]>
    
    public var parentId: UUID? = nil
}

extension PdfModel: nonisolated Comparable {
    public var hasPdf: Bool {
        fileUrl != nil
    }

    nonisolated public static func < (lhs: PdfModel, rhs: PdfModel) -> Bool {
        return assumeMainActorIsolated {
            lhs.name < rhs.name
    
        }
    }
}

extension PdfModel: nonisolated ItemLinkRegistable {}

extension PdfModel: nonisolated ItemDiffComparable {
    nonisolated public func merge(_ other: PdfModel) -> PdfModel {
        return assumeMainActorIsolated {
            let mergedCategory = category_.merged(other: other.category_)
            // Per-id union (not `entries_.merged`'s whole-array last-writer-wins) so a
            // bookmark added independently on two devices before syncing isn't silently
            // discarded; entries present on both sides get their own CRDT fields merged
            // via `PdfEntryModel.merge`. See CODE_AUDIT_Pdf §5.2.
            let allIds = Set(entries.map(\.id)).union(other.entries.map(\.id))
            let combined = allIds
                .map { id -> PdfEntryModel in
                    switch (entries.first { $0.id == id }, other.entries.first { $0.id == id }) {
                    case let (local?, remote?): return local.merge(remote)
                    case let (local?, nil): return local
                    case let (nil, remote?): return remote
                    case (nil, nil): return .empty(id)
                    }
                }
                .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
            // Merge the `update` marker CRDT too (not a fresh random UUID) so that
            // merging two otherwise-identical models is idempotent, matching
            // `CRDTDataUpdate.merged`'s own convention.
            let mergedUpdate = entries_.$update.merged(other: other.entries_.$update)
            let mergedEntries = CRDTDataUpdate(wrappedValue: combined, update: mergedUpdate)
            return PdfModel(
                id: id,
                name: name_.merged(other: other.name_),
                description: description_.merged(other: other.description_),
                tags: tags_.merged(other: other.tags_),
                category: mergedCategory,
                displayState: other.displayState,
                fileUrl: fileUrl_.merged(other: other.fileUrl_),
                entries: mergedEntries,
                parentId: other.parentId
            )
    
        }
    }

    nonisolated public func isSame(_ other: PdfModel) -> Bool {
        return assumeMainActorIsolated {
            guard entries.count == other.entries.count else { return false }
            // Compared by id, not position — entries can legitimately end up in a
            // different order on each side (e.g. after a merge). See CODE_AUDIT_Pdf §5.5.
            let otherEntriesById = Dictionary(uniqueKeysWithValues: other.entries.map { ($0.id, $0) })
            return name == other.name &&
            description == other.description &&
            tags == other.tags &&
            category == other.category &&
            fileUrl_.update == other.fileUrl_.update &&
            entries_.update == other.entries_.update &&
            parentId == other.parentId &&
            entries.allSatisfy { otherEntriesById[$0.id] == $0 }
        }
    }
    
    public var version: Int {
        fileUrl?.contentVersion ?? FileUrl.versionValue(of: fileUrl_.update)
    }
}

extension PdfModel: nonisolated ItemDuplicatable {
    nonisolated public func duplicate() -> PdfModel {
        return assumeMainActorIsolated {
            let copyName = duplicateName(from: name)
            return PdfModel(id: UUID(), name: copyName, description: description, tags: tags, category: category, displayState: displayState, fileUrl: nil, entries: entries.map { $0.duplicate() })
    
        }
    }
}

extension PdfModel: nonisolated ItemDataAccessable {
    nonisolated public static var empty: PdfModel { empty(UUID()) }
    nonisolated public static func empty(_ id: UUID) -> PdfModel {
        PdfModel(id: id, name: "")
    }
    nonisolated public static let typeId: NetworkModules = .pdf

    public func copy() -> PdfModel {
        PdfModel(id: id, name: name_, description: description_, tags: tags_, category: category_, displayState: displayState, fileUrl: fileUrl_, entries: entries_, parentId: parentId)
    }

    public func filter(filter: String, includeEntries: Bool) -> Bool {
        guard !filter.isEmpty else { return true }
        guard !(name.localizedStandardContains(filter) || description.localizedStandardContains(filter)) else { return true }
        guard specialCategory == false else { return false }
        return entries.contains {
            $0.filter(with: filter)
        }
    }

    public func isEqual(other: PdfModel) -> Bool {
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

    @MainActor public func replace(with model: PdfModel) -> Bool {
        guard self != model else { return false }
        name_ <=> model.name_
        description_ <=> model.description_
        tags_ <=> model.tags_
        category_ <=> model.category_
        displayState <=> model.displayState
        fileUrl_ <=> model.fileUrl_
        entries_ <=> model.entries_
        parentId <=> model.parentId
        return true
    }

    public subscript(id: UUID) -> PdfEntryModel {
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

extension PdfModel: nonisolated Codable {
    enum CodingKeys: CodingKey {
        case _id
        case _name_
        case _description_
        case _tags_
        case _category_
        case _displayState
        case _fileUrl_
        case _entries_
        case _parentId
    }

    nonisolated public final func encode(to encoder: Encoder) throws {
        try encoder.encodeOnMainActor { encoder in
            var container: KeyedEncodingContainer<PdfModel.CodingKeys> = encoder.container(keyedBy: PdfModel.CodingKeys.self)

            try container.encode(self.id, forKey: PdfModel.CodingKeys._id)
            try container.encode(self._name_, forKey: PdfModel.CodingKeys._name_)
            try container.encode(self._description_, forKey: PdfModel.CodingKeys._description_)
            try container.encode(self._tags_, forKey: PdfModel.CodingKeys._tags_)
            try container.encode(self._category_, forKey: PdfModel.CodingKeys._category_)
            try container.encode(self._displayState, forKey: PdfModel.CodingKeys._displayState)
            try container.encode(self._fileUrl_, forKey: PdfModel.CodingKeys._fileUrl_)
            try container.encode(self._entries_, forKey: PdfModel.CodingKeys._entries_)
            try container.encodeIfPresent(self._parentId, forKey: PdfModel.CodingKeys._parentId)
        }
    }
}

extension PdfModel: nonisolated Equatable, nonisolated Hashable {
    nonisolated public static func == (lhs: PdfModel, rhs: PdfModel) -> Bool {
        return assumeMainActorIsolated {
            lhs.id == rhs.id && lhs.isSame(rhs) && lhs.displayState == rhs.displayState
    
        }
    }

    nonisolated public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
