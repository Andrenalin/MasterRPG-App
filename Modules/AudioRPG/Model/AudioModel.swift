// @copyright André Trettin

import CoreRPG
import Foundation
import Observation

// MainActor-owned model. Sendable via global-actor isolation (no @unchecked):
// persistence crosses the Core Data boundary as AudioSnapshot, the .gmz wire
// format stays on this type's Codable (encode/decode run on the MainActor).
// Inits and the factories are nonisolated (they only initialize stored state) so
// decoding and generic factory requirements work off-main.
@MainActor @Observable
public final class AudioModel: nonisolated Identifiable {
    nonisolated init(id: UUID, name: String, description: String = "", tags: [String] = [], category: ItemListCategory = .music, displayState: Int = 0, fileUrl: FileUrl? = nil, entries: [AudioEntryModel] = [], parentId: UUID? = nil) {
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

    nonisolated init(id: UUID, name: CRDT<String>, description: CRDT<String>, tags: CRDT<[String]>, category: CRDT<ItemListCategory>, displayState: Int = 0, fileUrl: CRDTDataUpdate<FileUrl?>, entries: CRDTDataUpdate<[AudioEntryModel]>, parentId: UUID?) {
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
        let container: KeyedDecodingContainer<AudioModel.CodingKeys> = try decoder.container(keyedBy: AudioModel.CodingKeys.self)

        self.id = try container.decode(UUID.self, forKey: AudioModel.CodingKeys._id)
        self._name_ = try container.decode(CRDT<String>.self, forKey: AudioModel.CodingKeys._name_)
        self._description_ = try container.decode(CRDT<String>.self, forKey: AudioModel.CodingKeys._description_)
        self._tags_ = try container.decode(CRDT<[String]>.self, forKey: AudioModel.CodingKeys._tags_)
        self._category_ = try container.decode(CRDT<ItemListCategory>.self, forKey: AudioModel.CodingKeys._category_)
        self._displayState = try container.decode(Int.self, forKey: AudioModel.CodingKeys._displayState)
        self._fileUrl_ = try container.decode(CRDTDataUpdate<FileUrl?>.self, forKey: AudioModel.CodingKeys._fileUrl_)
        self._entries_ = try container.decode(CRDTDataUpdate<[AudioEntryModel]>.self, forKey: AudioModel.CodingKeys._entries_)
        self._parentId = try container.decodeIfPresent(UUID.self, forKey: AudioModel.CodingKeys._parentId)
    }

    // `let`: gives nonisolated access (Identifiable, hashing, protocol id) per SE-0434.
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
    var fileUrl_: CRDTDataUpdate<FileUrl?>

    public var entries: [AudioEntryModel] {
        get { entries_.wrappedValue }
        set { entries_.wrappedValue = newValue }
    }
    var entries_: CRDTDataUpdate<[AudioEntryModel]>

    public var parentId: UUID? = nil

    // only game properties
    public var players: [UUID] = []
}

extension AudioModel {
    var hasAudio: Bool {
        fileUrl != nil
    }
}

extension AudioModel: nonisolated Comparable {
    // Nonisolated shim: Comparable is a nonisolated protocol; all real call sites
    // are on the MainActor — assumeIsolated turns a violation into a trap.
    nonisolated public static func < (lhs: AudioModel, rhs: AudioModel) -> Bool {
        assumeMainActorIsolated {
            lhs.name < rhs.name
        }
    }
}

extension AudioModel: nonisolated ItemGameReportable {}
extension AudioModel: nonisolated ItemLinkRegistrable {}

extension AudioModel: nonisolated ItemDiffComparable {
    // Legacy concrete shims remain nonisolated for direct Equatable-style calls.
    // Generic ItemDiffComparable access is MainActor-isolated by the protocol.
    nonisolated public func merge(_ other: AudioModel) -> AudioModel {
        assumeMainActorIsolated {
            mergeOnMain(other)
        }
    }

    @MainActor private func mergeOnMain(_ other: AudioModel) -> AudioModel {
        let mergedCategory = category_.merged(other: other.category_)
        let mergedEntries: CRDTDataUpdate<[AudioEntryModel]>
        if mergedCategory.wrappedValue == .folder {
            // Deterministic union (name, then id). See CODE_AUDIT_18 §9.9.
            let combined = FolderEntryMerge.merged(local: entries, remote: other.entries, id: \.id, name: \.name)
            mergedEntries = CRDTDataUpdate(wrappedValue: combined)
        } else {
            mergedEntries = entries_.merged(other: other.entries_)
        }
        return AudioModel(
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

    nonisolated public func isSame(_ other: AudioModel) -> Bool {
        assumeMainActorIsolated {
            name == other.name &&
            description == other.description &&
            tags == other.tags &&
            category == other.category &&
            fileUrl_.update == other.fileUrl_.update &&
            entries_.update == other.entries_.update &&
            parentId == other.parentId &&
            // sanity checks
            entries.count == other.entries.count &&
            entries.enumerated().allSatisfy { index, entry in
                entry == other.entries[index]
            }
        }
    }

    public var version: Int {
        fileUrl?.contentVersion ?? FileUrl.versionValue(of: fileUrl_.update)
    }
}

extension AudioModel: nonisolated ItemDuplicatable {
    // Nonisolated shim remains for legacy concrete callers. Generic item access
    // is MainActor-isolated by ItemDuplicatable and ItemDataAccessible.
    nonisolated public func duplicate() -> AudioModel {
        assumeMainActorIsolated {
            let copyName = duplicateName(from: name)
            return AudioModel(id: UUID(), name: copyName, description: description, tags: tags, category: category, displayState: displayState, fileUrl: nil, entries: entries.map { $0.duplicate() }, parentId: parentId)
        }
    }
}

extension AudioModel: nonisolated ItemDataAccessible {
    // Nonisolated: satisfies the nonisolated factory requirements; the init only
    // initializes stored state.
    nonisolated public static var empty: AudioModel { empty(UUID()) }
    nonisolated public static func empty(_ id: UUID) -> AudioModel {
        AudioModel(id: id, name: "")
    }
    nonisolated public static let typeId: NetworkModules = .audio

    public func copy() -> AudioModel {
        AudioModel(id: id, name: name_, description: description_, tags: tags_, category: category_, displayState: displayState, fileUrl: fileUrl_, entries: entries_, parentId: parentId)
    }

    public func filter(filter: String, includeEntries: Bool) -> Bool {
        guard !filter.isEmpty else { return true }
        guard !(name.localizedStandardContains(filter) || description.localizedStandardContains(filter)) else { return true }
        return false
    }

    public func isEqual(other: AudioModel) -> Bool {
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

    @MainActor public func replace(with model: AudioModel) -> Bool {
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

    public subscript(id: UUID) -> AudioEntryModel {
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
        let index = entries.firstIndex(where: { $0.audioId == entryId }) ?? -1
        return "\(index + 1): \(name.withoutLink())"
    }
}

extension AudioModel: nonisolated Codable {
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

    // Nonisolated shim: Codable's encode is a nonisolated requirement; export hops
    // to the MainActor before encoding (see ExportControllable.extract).
    nonisolated public final func encode(to encoder: Encoder) throws {
        try encoder.encodeOnMainActor { encoder in
            try encodeOnMain(to: encoder)
        }
    }

    @MainActor private func encodeOnMain(to encoder: Encoder) throws {
        var container: KeyedEncodingContainer<AudioModel.CodingKeys> = encoder.container(keyedBy: AudioModel.CodingKeys.self)

        try container.encode(self.id, forKey: AudioModel.CodingKeys._id)
        try container.encode(self._name_, forKey: AudioModel.CodingKeys._name_)
        try container.encode(self._description_, forKey: AudioModel.CodingKeys._description_)
        try container.encode(self._tags_, forKey: AudioModel.CodingKeys._tags_)
        try container.encode(self._category_, forKey: AudioModel.CodingKeys._category_)
        try container.encode(self._displayState, forKey: AudioModel.CodingKeys._displayState)
        try container.encode(self._fileUrl_, forKey: AudioModel.CodingKeys._fileUrl_)
        try container.encode(self._entries_, forKey: AudioModel.CodingKeys._entries_)
        try container.encodeIfPresent(self._parentId, forKey: AudioModel.CodingKeys._parentId)
    }
}

extension AudioModel: nonisolated Equatable, nonisolated Hashable {
    // Nonisolated shim: Equatable is a nonisolated protocol; content comparison
    // requires model state, so the body runs isolated via assumeIsolated.
    nonisolated public static func == (lhs: AudioModel, rhs: AudioModel) -> Bool {
        assumeMainActorIsolated {
            lhs.id == rhs.id && lhs.isSame(rhs) && lhs.displayState == rhs.displayState
        }
    }

    // id is an immutable let — hashing is safely nonisolated.
    nonisolated public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
