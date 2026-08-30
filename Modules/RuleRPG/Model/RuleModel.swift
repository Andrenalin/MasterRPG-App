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

// MARK: - Foundry factories

public extension RuleModel {
    /// Maps a normalized system-compendium rule into an editable RuleRPG model.
    /// The complete `FoundryRuleDefinition` remains available through `sourcePayload`.
    @MainActor
    static func foundry(
        _ rule: FoundryRuleDefinition,
        manifest: FoundrySystemManifest,
        id: UUID? = nil,
        identityNamespace: String? = nil,
        parentId: UUID? = nil
    ) -> RuleModel {
        let metadata = RuleSourceMetadata(
            sourceIdentifier: rule.id,
            systemID: manifest.id,
            systemTitle: FoundryTextDecoder.decodedText(manifest.title),
            systemVersion: manifest.version,
            packageIdentifier: "\(manifest.id).\(rule.packName)",
            packageName: FoundryTextDecoder.decodedText(rule.packName),
            documentID: rule.documentID,
            documentType: FoundryTextDecoder.decodedText(rule.documentType),
            subtype: FoundryTextDecoder.decodedText(rule.subtype),
            ruleCategory: FoundryTextDecoder.decodedText(rule.category.rawValue),
            imagePath: rule.imagePath ?? ""
        )
        let generatedEntries = foundryEntries(
            rule: rule,
            sourceIdentifier: identityNamespace ?? rule.id
        )
        let generatedTags = orderedUnique(
            rule.tags + [rule.category.rawValue, rule.subtype, manifest.title, "Foundry VTT"]
        )

        return RuleModel(
            id: id ?? rule.masterRPGID,
            name: FoundryTextDecoder.decodedText(rule.name),
            description: readableText(fromHTML: rule.descriptionHTML),
            tags: generatedTags,
            category: .rules,
            entries: generatedEntries,
            sourceMetadata: metadata,
            sourcePayload: .foundryRule(rule),
            parentId: parentId
        )
    }

    /// Maps a generic Foundry Item/document projection into RuleRPG while retaining its raw JSON.
    @MainActor
    static func foundryDocument(
        id: UUID,
        name: String,
        descriptionHTML: String?,
        tags: [String],
        documentType: String,
        subtype: String,
        rawData: FoundryJSONValue,
        parentId: UUID?,
        packageIdentifier: String,
        identityNamespace: String? = nil
    ) -> RuleModel {
        let sourceIdentifier = rawData["_id"]?.stringValue ?? id.uuidString.lowercased()
        let systemID = rawData.value(at: "_stats.systemId")?.stringValue ?? ""
        let systemVersion = rawData.value(at: "_stats.systemVersion")?.stringValue ?? ""
        let category = rawData["type"]?.stringValue ?? subtype
        let imagePath = rawData["img"]?.stringValue ?? ""
        let metadata = RuleSourceMetadata(
            sourceIdentifier: sourceIdentifier,
            systemID: systemID,
            systemVersion: systemVersion,
            packageIdentifier: packageIdentifier,
            packageName: FoundryTextDecoder.decodedText(packageIdentifier),
            documentID: sourceIdentifier,
            documentType: FoundryTextDecoder.decodedText(documentType),
            subtype: FoundryTextDecoder.decodedText(subtype),
            ruleCategory: FoundryTextDecoder.decodedText(category),
            imagePath: imagePath
        )
        let values = hierarchicalValues(
            rawData["system"] ?? rawData,
            sourceIdentifier: identityNamespace ?? sourceIdentifier
        )

        return RuleModel(
            id: id,
            name: FoundryTextDecoder.decodedText(name),
            description: readableText(fromHTML: descriptionHTML),
            tags: orderedUnique(tags + [subtype, "Foundry VTT"]),
            category: .rules,
            entries: values,
            sourceMetadata: metadata,
            sourcePayload: .foundryDocument(rawData),
            parentId: parentId
        )
    }

}

private extension RuleModel {
    static func foundryEntries(
        rule: FoundryRuleDefinition,
        sourceIdentifier: String
    ) -> [RuleEntryModel] {
        var result = hierarchicalValues(
            projectedRuleValues(rule.values),
            sourceIdentifier: sourceIdentifier
        )

        result.append(contentsOf: rule.references.enumerated().map { index, reference in
            let label = reference.label?.isEmpty == false
                ? FoundryTextDecoder.decodedText(reference.label ?? reference.target)
                : FoundryTextDecoder.decodedText(reference.target)
            var details = "**Target:** \(reference.target)"
            if let packName = reference.packName, !packName.isEmpty {
                details += "\n\n**Pack:** \(FoundryTextDecoder.decodedText(packName))"
            }
            if let documentID = reference.documentID, !documentID.isEmpty {
                details += "\n\n**Document:** \(documentID)"
            }
            return RuleEntryModel(
                id: FoundryRuleIdentity.uuid(
                    for: "\(sourceIdentifier)#reference#\(reference.sourcePath)#\(index)"
                ),
                name: label,
                content: details,
                kind: .reference
            )
        })

        result.append(contentsOf: rule.embeddedRules.map { embedded in
            var sections = [readableText(fromHTML: embedded.descriptionHTML)]
                .filter { !$0.isEmpty }
            let values = embedded.values.map {
                "- **\(FoundryTextDecoder.decodedText($0.path)):** \(presentation($0.value))"
            }
            if !values.isEmpty {
                sections.append("**Values**\n\(values.joined(separator: "\n"))")
            }
            if !embedded.references.isEmpty {
                let references = embedded.references.enumerated().map { index, reference in
                    foundryReferenceDetails(reference, index: index)
                }
                sections.append("**References**\n\n\(references.joined(separator: "\n\n"))")
            }
            if !embedded.effects.isEmpty {
                let effects = embedded.effects.enumerated().map { index, effect in
                    let name = effect.name.isEmpty
                        ? "Effect \(index + 1)"
                        : FoundryTextDecoder.decodedText(effect.name)
                    return "**\(name)**\n\(foundryEffectDetails(effect))"
                }
                sections.append("**Effects**\n\n\(effects.joined(separator: "\n\n"))")
            }
            return RuleEntryModel(
                id: FoundryRuleIdentity.uuid(
                    for: "\(sourceIdentifier)#embedded#\(embedded.id)"
                ),
                name: FoundryTextDecoder.decodedText(embedded.name),
                content: sections.joined(separator: "\n\n"),
                kind: .embeddedRule
            )
        })

        result.append(contentsOf: rule.effects.enumerated().map { index, effect in
            return RuleEntryModel(
                id: FoundryRuleIdentity.uuid(
                    for: "\(sourceIdentifier)#effect#\(effect.id)"
                ),
                name: effect.name.isEmpty
                    ? "Effect \(index + 1)"
                    : FoundryTextDecoder.decodedText(effect.name),
                content: foundryEffectDetails(effect),
                kind: .effect
            )
        })
        return result
    }

    static func foundryReferenceDetails(
        _ reference: FoundryRuleReference,
        index: Int
    ) -> String {
        let label = reference.label?.isEmpty == false
            ? FoundryTextDecoder.decodedText(reference.label ?? reference.target)
            : FoundryTextDecoder.decodedText(reference.target)
        var lines = [
            "**Reference \(index + 1): \(label)**",
            "- **Target:** \(reference.target)",
            "- **Type:** \(reference.kind.rawValue)",
            "- **Source:** \(reference.sourcePath)",
            "- **Token:** \(reference.rawToken)",
        ]
        if let packName = reference.packName, !packName.isEmpty {
            lines.append("- **Pack:** \(FoundryTextDecoder.decodedText(packName))")
        }
        if let documentID = reference.documentID, !documentID.isEmpty {
            lines.append("- **Document:** \(documentID)")
        }
        return lines.joined(separator: "\n")
    }

    static func foundryEffectDetails(_ effect: FoundryRuleEffect) -> String {
        var lines = [
            "- **ID:** \(effect.id)",
            "- **Disabled:** \(effect.isDisabled ? "yes" : "no")",
            "- **Transfers to actor:** \(effect.transfersToActor ? "yes" : "no")",
        ]
        if !effect.statuses.isEmpty {
            lines.append(
                "- **Statuses:** \(effect.statuses.map(FoundryTextDecoder.decodedText).joined(separator: ", "))"
            )
        }
        if let duration = effect.duration {
            lines.append("- **Duration:** \(presentation(duration))")
        }
        if !effect.changes.isEmpty {
            lines.append("**Changes**")
            lines.append(contentsOf: effect.changes.map { change in
                let priority = change.priority.map { ", priority \($0)" } ?? ""
                return "- **\(change.path):** \(presentation(change.operand)) (mode \(change.mode)\(priority))"
            })
        }
        return lines.joined(separator: "\n")
    }

    static func hierarchicalValues(
        _ value: FoundryJSONValue,
        sourceIdentifier: String
    ) -> [RuleEntryModel] {
        hierarchicalValues(
            FoundryValueHierarchy.nodes(from: value),
            sourceIdentifier: sourceIdentifier
        )
    }

    static func hierarchicalValues(
        _ values: [FoundryRuleValue],
        sourceIdentifier: String
    ) -> [RuleEntryModel] {
        hierarchicalValues(
            FoundryValueHierarchy.nodes(from: values),
            sourceIdentifier: sourceIdentifier
        )
    }

    static func hierarchicalValues(
        _ nodes: [FoundryValueNode],
        sourceIdentifier: String
    ) -> [RuleEntryModel] {
        let maximumPresentedValues = 500
        let valueCount = nodes.reduce(0) { $0 + $1.valueCount }
        var remainingValues = maximumPresentedValues
        var result = projectedValueEntries(
            nodes,
            sourceIdentifier: sourceIdentifier,
            parentId: nil,
            remainingValues: &remainingValues
        )
        if valueCount > maximumPresentedValues {
            result.append(RuleEntryModel(
                id: FoundryRuleIdentity.uuid(for: "\(sourceIdentifier)#source#remaining-values"),
                name: "Additional source values",
                content: "\(valueCount - maximumPresentedValues) values remain available in the lossless source payload.",
                kind: .source
            ))
        }
        return result
    }

    static func projectedValueEntries(
        _ nodes: [FoundryValueNode],
        sourceIdentifier: String,
        parentId: UUID?,
        remainingValues: inout Int
    ) -> [RuleEntryModel] {
        var entries: [RuleEntryModel] = []
        for node in nodes {
            guard remainingValues > 0 else { break }
            let pathIdentity = valuePathIdentity(node.pathComponents)
            if node.children.isEmpty, let value = node.value {
                remainingValues -= 1
                entries.append(RuleEntryModel(
                    id: FoundryRuleIdentity.uuid(
                        for: "\(sourceIdentifier)#value#\(pathIdentity)"
                    ),
                    name: FoundryTextDecoder.decodedText(node.component),
                    content: presentation(value),
                    kind: .value,
                    parentId: parentId
                ))
                continue
            }

            let groupId = FoundryRuleIdentity.uuid(
                for: "\(sourceIdentifier)#value-group#\(pathIdentity)"
            )
            var descendants: [RuleEntryModel] = []
            if let value = node.value, remainingValues > 0 {
                remainingValues -= 1
                descendants.append(RuleEntryModel(
                    id: FoundryRuleIdentity.uuid(
                        for: "\(sourceIdentifier)#value#\(pathIdentity)#own"
                    ),
                    name: "value",
                    content: presentation(value),
                    kind: .value,
                    parentId: groupId
                ))
            }
            descendants.append(contentsOf: projectedValueEntries(
                node.children,
                sourceIdentifier: sourceIdentifier,
                parentId: groupId,
                remainingValues: &remainingValues
            ))
            guard !descendants.isEmpty else { continue }

            entries.append(RuleEntryModel(
                id: groupId,
                name: FoundryTextDecoder.decodedText(node.component),
                content: "",
                kind: .group,
                parentId: parentId
            ))
            entries.append(contentsOf: descendants)
        }
        return entries
    }

    static func projectedRuleValues(
        _ values: [FoundryRuleValue]
    ) -> [FoundryRuleValue] {
        let paths = values.map {
            $0.path.split(separator: ".", omittingEmptySubsequences: true).map(String.init)
        }
        let hasCommonTechnicalSystemRoot = !paths.isEmpty && paths.allSatisfy {
            $0.count > 1 && $0.first == "system"
        }
        guard hasCommonTechnicalSystemRoot else { return values }
        return zip(values, paths).map { value, path in
            FoundryRuleValue(
                path: path.dropFirst().joined(separator: "."),
                value: value.value
            )
        }
    }

    static func valuePathIdentity(_ components: [String]) -> String {
        guard !components.isEmpty else { return "root" }
        return components.map { component in
            "\(component.utf8.count):\(component)"
        }.joined()
    }

    static func presentation(_ value: FoundryJSONValue) -> String {
        switch value {
        case .string(let value): return FoundryTextDecoder.plainText(fromHTML: value)
        case .integer(let value): return value.formatted()
        case .unsignedInteger(let value): return value.formatted()
        case .number(let value): return value.formatted(.number)
        case .bool(let value): return value ? "true" : "false"
        case .null: return "null"
        case .array(let values): return values.map(presentation).joined(separator: ", ")
        case .object:
            guard let data = try? JSONEncoder().encode(value),
                  let text = String(data: data, encoding: .utf8) else { return "" }
            return text
        }
    }

    static func readableText(fromHTML html: String?) -> String {
        FoundryTextDecoder.plainText(fromHTML: html)
    }

    static func orderedUnique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for value in values {
            let decoded = FoundryTextDecoder.decodedText(value)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !decoded.isEmpty,
                  seen.insert(decoded.localizedLowercase).inserted else { continue }
            result.append(decoded)
        }
        return result
    }
}

// MARK: - Item behavior

extension RuleModel: ItemLinkRegistable {
    public var linkRegisterModels: [LinkRegisterModel] {
        linkRegisterModels(description: description) + entries.flatMap(linkRegisterModels(entry:))
    }

    public func changedLinkRegisterModels(
        oldValue: RuleModel
    ) -> (added: [LinkRegisterModel], removed: [LinkRegisterModel]) {
        let oldByID = Dictionary(uniqueKeysWithValues: oldValue.entries.map { ($0.id, $0) })
        let newByID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
        let oldIDs = Set(oldByID.keys)
        let newIDs = Set(newByID.keys)

        var added: [LinkRegisterModel] = []
        var removed: [LinkRegisterModel] = []
        if oldValue.description != description {
            removed.append(contentsOf: oldValue.linkRegisterModels(description: oldValue.description))
            added.append(contentsOf: linkRegisterModels(description: description))
        }

        added.append(contentsOf: newIDs.subtracting(oldIDs).flatMap { id in
            newByID[id].map(linkRegisterModels(entry:)) ?? []
        })
        removed.append(contentsOf: oldIDs.subtracting(newIDs).flatMap { id in
            oldByID[id].map(oldValue.linkRegisterModels(entry:)) ?? []
        })

        for id in oldIDs.intersection(newIDs) {
            guard let oldEntry = oldByID[id], let newEntry = newByID[id], oldEntry != newEntry else { continue }
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
        return entry.links(for: entry.content).map { link in
            LinkRegisterModel(link: link, source: source)
        }
    }
}

extension RuleModel: ItemDiffComparable {
    public func merge(_ other: RuleModel) -> RuleModel {
        let mergedCategory = category_.merged(other: other.category_)
        let mergedEntries: CRDTDataUpdate<[RuleEntryModel]>
        if mergedCategory.wrappedValue == .folder {
            let allIDs = Set(entries.map(\.id)).union(other.entries.map(\.id))
            let combined = allIDs
                .compactMap { id in entries.first { $0.id == id } ?? other.entries.first { $0.id == id } }
                .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
            mergedEntries = CRDTDataUpdate(wrappedValue: combined)
        } else {
            mergedEntries = entries_.merged(other: other.entries_)
        }
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

    public var version: Int {
        StableVersionDigest.digest(CanonicalRuleContent(self))
    }
}

extension RuleModel: ItemDuplicatable {
    public func duplicate() -> RuleModel {
        var duplicatedEntryIDs: [UUID: UUID] = [:]
        for entry in entries {
            if duplicatedEntryIDs[entry.id] == nil {
                duplicatedEntryIDs[entry.id] = UUID()
            }
        }
        let duplicatedEntries = entries.compactMap { entry -> RuleEntryModel? in
            guard let duplicatedID = duplicatedEntryIDs[entry.id] else { return nil }
            return entry.duplicate(
                id: duplicatedID,
                parentId: entry.parentId.flatMap { duplicatedEntryIDs[$0] }
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

extension RuleModel: ItemReferencable {}

extension RuleModel: ItemDataAccessable {
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
    let sourcePayload: RuleSourcePayload?
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
        sourcePayload = model.sourcePayload
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
