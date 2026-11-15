// @copyright André Trettin

import CoreRPG
import Foundation
import Observation

/// An editable rule together with the lossless normalized payload from which it was imported.
@MainActor @Observable
public final class RuleModel: nonisolated Identifiable {
    nonisolated public init(
        id: UUID,
        name: String,
        description: String = "",
        tags: [String] = [],
        category: ItemListCategory = .rules,
        displayState: Int = 0,
        entries: [RuleEntryModel] = [],
        sourceMetadata: RuleSourceMetadata = .empty,
        sourcePayload: RuleSourcePayload? = nil,
        parentId: UUID? = nil
    ) {
        self.id = id
        _name_ = CRDT(wrappedValue: name)
        _description_ = CRDT(wrappedValue: description)
        _tags_ = CRDT(wrappedValue: tags)
        _category_ = CRDT(wrappedValue: category)
        self._displayState = displayState
        _entries_ = CRDTDataUpdate(wrappedValue: entries)
        _sourceMetadata_ = CRDT(wrappedValue: sourceMetadata)
        _sourcePayload_ = CRDT(wrappedValue: sourcePayload)
        self._parentId = parentId
    }

    nonisolated init(
        id: UUID,
        name: CRDT<String>,
        description: CRDT<String>,
        tags: CRDT<[String]>,
        category: CRDT<ItemListCategory>,
        displayState: Int,
        entries: CRDTDataUpdate<[RuleEntryModel]>,
        sourceMetadata: CRDT<RuleSourceMetadata>,
        sourcePayload: CRDT<RuleSourcePayload?>,
        parentId: UUID?
    ) {
        self.id = id
        _name_ = name
        _description_ = description
        _tags_ = tags
        _category_ = category
        self._displayState = displayState
        _entries_ = entries
        _sourceMetadata_ = sourceMetadata
        _sourcePayload_ = sourcePayload
        self._parentId = parentId
    }

    nonisolated public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        _name_ = try container.decode(CRDT<String>.self, forKey: .name)
        _description_ = try container.decode(CRDT<String>.self, forKey: .description)
        _tags_ = try container.decode(CRDT<[String]>.self, forKey: .tags)
        _category_ = try container.decode(CRDT<ItemListCategory>.self, forKey: .category)
        _displayState = try container.decode(Int.self, forKey: .displayState)
        _entries_ = try container.decode(CRDTDataUpdate<[RuleEntryModel]>.self, forKey: .entries)
        _sourceMetadata_ = try container.decodeIfPresent(
            CRDT<RuleSourceMetadata>.self,
            forKey: .sourceMetadata
        ) ?? CRDT(wrappedValue: .empty)
        _sourcePayload_ = try container.decodeIfPresent(
            CRDT<RuleSourcePayload?>.self,
            forKey: .sourcePayload
        ) ?? CRDT(wrappedValue: nil)
        _parentId = try container.decodeIfPresent(UUID.self, forKey: .parentId)
    }

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

    public var entries: [RuleEntryModel] {
        get { entries_.wrappedValue }
        set { entries_.wrappedValue = newValue }
    }
    var entries_: CRDTDataUpdate<[RuleEntryModel]>

    public var sourceMetadata: RuleSourceMetadata {
        get { sourceMetadata_.wrappedValue }
        set { sourceMetadata_.wrappedValue = newValue }
    }
    var sourceMetadata_: CRDT<RuleSourceMetadata>

    public var sourcePayload: RuleSourcePayload? {
        get { sourcePayload_.wrappedValue }
        set { sourcePayload_.wrappedValue = newValue }
    }
    var sourcePayload_: CRDT<RuleSourcePayload?>

    public var parentId: UUID?
}

// MARK: - Item behavior

extension RuleModel: ItemLinkRegistrable {
    public var linkRegisterModels: [LinkRegisterModel] {
        linkRegisterModels(description: description) + entries.flatMap(linkRegisterModels(entry:))
    }

    public func changedLinkRegisterModels(
        oldValue: RuleModel
    ) -> (added: [LinkRegisterModel], removed: [LinkRegisterModel]) {
        // First-wins, not a trapping `uniqueKeysWithValues`: imported rules can repeat an
        // entry id. See CODE_AUDIT_21 §6.8.
        let oldById = Dictionary(oldValue.entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let newById = Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let oldIds = Set(oldById.keys)
        let newIds = Set(newById.keys)

        var added: [LinkRegisterModel] = []
        var removed: [LinkRegisterModel] = []
        if oldValue.description != description {
            removed.append(contentsOf: oldValue.linkRegisterModels(description: oldValue.description))
            added.append(contentsOf: linkRegisterModels(description: description))
        }

        added.append(contentsOf: newIds.subtracting(oldIds).flatMap { id in
            newById[id].map(linkRegisterModels(entry:)) ?? []
        })
        removed.append(contentsOf: oldIds.subtracting(newIds).flatMap { id in
            oldById[id].map(oldValue.linkRegisterModels(entry:)) ?? []
        })

        for id in oldIds.intersection(newIds) {
            guard let oldEntry = oldById[id], let newEntry = newById[id], oldEntry != newEntry else { continue }
            removed.append(contentsOf: oldValue.linkRegisterModels(entry: oldEntry))
            added.append(contentsOf: linkRegisterModels(entry: newEntry))
        }
        return (added, removed)
    }

    private func linkRegisterModels(description: String) -> [LinkRegisterModel] {
        let source = ItemRowModel(itemId: id, typeId: .rule)
        return LinkReplaceController.links(for: description).map { link in
            LinkRegisterModel(link: link, source: source)
        }
    }

    private func linkRegisterModels(entry: RuleEntryModel) -> [LinkRegisterModel] {
        let source = ItemRowModel(itemId: id, entryId: entry.id, typeId: .rule)
        return LinkReplaceController.links(for: entry.content).map { link in
            LinkRegisterModel(link: link, source: source)
        }
    }
}

extension RuleModel: ItemDiffComparable {
    public func merge(_ other: RuleModel) -> RuleModel {
        let mergedCategory = category_.merged(other: other.category_)
        // Folders union their members, other categories last-writer-wins. See CODE_AUDIT_Folder §9.8.
        let mergedEntries = FolderEntryMerge.mergedEntries(category: mergedCategory.wrappedValue, local: entries_, remote: other.entries_, id: \.id, name: \.name, childId: \.childId)
        return RuleModel(
            id: id,
            name: name_.merged(other: other.name_),
            description: description_.merged(other: other.description_),
            tags: tags_.merged(other: other.tags_),
            category: mergedCategory,
            displayState: other.displayState,
            entries: mergedEntries,
            sourceMetadata: sourceMetadata_.merged(other: other.sourceMetadata_),
            sourcePayload: sourcePayload_.merged(other: other.sourcePayload_),
            parentId: other.parentId
        )
    }

    public func isSame(_ other: RuleModel) -> Bool {
        name == other.name &&
        description == other.description &&
        tags == other.tags &&
        category == other.category &&
        sourceMetadata == other.sourceMetadata &&
        sourcePayload == other.sourcePayload &&
        entries_.update == other.entries_.update &&
        parentId == other.parentId &&
        entries == other.entries
    }

    /// The version on the wire, from what a player holds: the raw Foundry payload is left out.
    /// A package for players does not carry it (see `ExportController.playerExportData`), so the
    /// master's and a player's copy must agree without it, and the digest no longer encodes
    /// hundreds of KB of source JSON on every availability check. See CODE_AUDIT_26 §7.21.
    public var version: Int {
        StableVersionDigest.digest(CanonicalRuleContent(self))
    }
}

extension RuleModel: ItemDuplicatable {
    public func duplicate() -> RuleModel {
        var duplicatedEntryIds: [UUID: UUID] = [:]
        for entry in entries {
            if duplicatedEntryIds[entry.id] == nil {
                duplicatedEntryIds[entry.id] = UUID()
            }
        }
        let duplicatedEntries = entries.compactMap { entry -> RuleEntryModel? in
            guard let duplicatedId = duplicatedEntryIds[entry.id] else { return nil }
            return entry.duplicate(
                id: duplicatedId,
                parentId: entry.parentId.flatMap { duplicatedEntryIds[$0] }
            )
        }
        return RuleModel(
            id: UUID(),
            name: duplicateName(from: name),
            description: description,
            tags: tags,
            category: category,
            displayState: displayState,
            entries: duplicatedEntries,
            sourceMetadata: sourceMetadata,
            sourcePayload: sourcePayload,
            parentId: nil
        )
    }
}


extension RuleModel: ItemDataAccessible {
    public var fileUrl: FileUrl? {
        get { nil }
        set {}
    }

    nonisolated public static var empty: RuleModel { empty(UUID()) }

    nonisolated public static func empty(_ id: UUID) -> RuleModel {
        RuleModel(id: id, name: "")
    }

    nonisolated public static let typeId: NetworkModules = .rule

    public func copy() -> RuleModel {
        RuleModel(
            id: id,
            name: name_,
            description: description_,
            tags: tags_,
            category: category_,
            displayState: displayState,
            entries: entries_,
            sourceMetadata: sourceMetadata_,
            sourcePayload: sourcePayload_,
            parentId: parentId
        )
    }

    public func filter(filter: String, includeEntries: Bool) -> Bool {
        guard !filter.isEmpty else { return true }
        let metadata = sourceMetadata
        if name.localizedStandardContains(filter) ||
            description.localizedStandardContains(filter) ||
            tags.contains(where: { $0.localizedStandardContains(filter) }) ||
            metadata.systemTitle.localizedStandardContains(filter) ||
            metadata.packageName.localizedStandardContains(filter) ||
            metadata.subtype.localizedStandardContains(filter) {
            return true
        }
        guard includeEntries, !specialCategory else { return false }
        return entries.contains { $0.filter(with: filter) }
    }

    public func isEqual(other: RuleModel) -> Bool { self == other }

    public var isGroupHiddenToggle: Bool {
        get { isGroupHidden }
        set {
            displayState = newValue
                ? DisplayStateMask.groupHidden.set(on: displayState)
                : DisplayStateMask.groupHidden.reset(on: displayState)
        }
    }

    public func replace(with model: RuleModel) -> Bool {
        guard self != model else { return false }
        name_ <=> model.name_
        description_ <=> model.description_
        tags_ <=> model.tags_
        category_ <=> model.category_
        displayState <=> model.displayState
        entries_ <=> model.entries_
        sourceMetadata_ <=> model.sourceMetadata_
        sourcePayload_ <=> model.sourcePayload_
        parentId <=> model.parentId
        return true
    }

    public subscript(id: UUID) -> RuleEntryModel {
        get { entries.first(where: { $0.id == id }) ?? .empty(id) }
        set {
            guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
            entries[index] = newValue
        }
    }
}

public extension RuleModel {
    var reviewProperties: [ReviewCustomProperty] {
        [
            ReviewCustomProperty(displayName: String(localized: "System", bundle: .ruleModule)) {
                ReviewPropertyValue(($0 as? RuleModel)?.sourceMetadata.systemTitle ?? "")
            },
            ReviewCustomProperty(displayName: String(localized: "Package", bundle: .ruleModule)) {
                ReviewPropertyValue(($0 as? RuleModel)?.sourceMetadata.packageName ?? "")
            },
            ReviewCustomProperty(displayName: String(localized: "Rule Type", bundle: .ruleModule)) {
                ReviewPropertyValue(($0 as? RuleModel)?.sourceMetadata.subtype ?? "")
            }
        ]
    }
}

extension RuleModel: Codable {
    enum CodingKeys: CodingKey {
        case id
        case name
        case description
        case tags
        case category
        case displayState
        case entries
        case sourceMetadata
        case sourcePayload
        case parentId
    }

    nonisolated public func encode(to encoder: any Encoder) throws {
        try encoder.encodeOnMainActor { encoder in
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(name_, forKey: .name)
            try container.encode(description_, forKey: .description)
            try container.encode(tags_, forKey: .tags)
            try container.encode(category_, forKey: .category)
            try container.encode(displayState, forKey: .displayState)
            try container.encode(entries_, forKey: .entries)
            try container.encode(sourceMetadata_, forKey: .sourceMetadata)
            try container.encode(sourcePayload_, forKey: .sourcePayload)
            try container.encodeIfPresent(parentId, forKey: .parentId)
        }
    }
}

extension RuleModel: nonisolated Equatable, nonisolated Hashable {
    nonisolated public static func == (lhs: RuleModel, rhs: RuleModel) -> Bool {
        assumeMainActorIsolated {
            lhs.id == rhs.id && lhs.displayState == rhs.displayState && lhs.isSame(rhs)
        }
    }

    nonisolated public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

private struct CanonicalRuleContent: Codable, Sendable {
    let id: UUID
    let name: String
    let description: String
    let tags: [String]
    let category: ItemListCategory
    let displayState: Int
    let entries: [RuleEntryModel]
    let sourceMetadata: RuleSourceMetadata
    let parentId: UUID?

    @MainActor
    init(_ model: RuleModel) {
        id = model.id
        name = model.name
        description = model.description
        tags = model.tags
        category = model.category
        displayState = model.displayState
        entries = model.entries
        sourceMetadata = model.sourceMetadata
        parentId = model.parentId
    }
}

#if DEBUG
public extension RuleModel {
    @MainActor
    static func fixture(
        id: UUID = UUID(uuidString: "D447D27A-840D-4EC7-A8B4-04695732A284") ?? UUID(),
        name: String = "Rule",
        description: String = "Rule description",
        tags: [String] = ["rules"],
        category: ItemListCategory = .rules,
        displayState: Int = 0,
        entries: [RuleEntryModel] = [.fixture()],
        sourceMetadata: RuleSourceMetadata = .empty,
        sourcePayload: RuleSourcePayload? = nil,
        parentId: UUID? = nil
    ) -> RuleModel {
        RuleModel(
            id: id,
            name: name,
            description: description,
            tags: tags,
            category: category,
            displayState: displayState,
            entries: entries,
            sourceMetadata: sourceMetadata,
            sourcePayload: sourcePayload,
            parentId: parentId
        )
    }
}
#endif
