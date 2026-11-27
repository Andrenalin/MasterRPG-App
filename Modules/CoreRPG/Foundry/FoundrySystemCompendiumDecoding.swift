// @copyright André Trettin

import Foundation

// Extracted from FoundrySystemPackageReader.swift per CODE_AUDIT §9.8 — decodes a system
// package's LevelDB-backed compendiums into `FoundryCompendium`/`FoundryRuleDefinition` values.
// `FoundryCanonicalKey` (Canonical Identifiers) travels with it since it's used exclusively by
// `FoundryCompendiumDecoder` and nothing else in the main file.

// MARK: - LevelDB Compendium Decoding

struct FoundryCompendiumDecoder {
    struct Result {
        let compendium: FoundryCompendium
        let diagnostics: [FoundryImportDiagnostic]
    }

    let systemId: String
    let pack: FoundryPackManifest
    let maximumDocumentCount: Int

    func decode(_ records: [FoundryLevelDBRecord]) throws -> Result {
        var latest: [String: FoundryLevelDBRecord] = [:]
        for record in records {
            if let current = latest[record.key] {
                if current.sequence > record.sequence { continue }
                if current.sequence == record.sequence {
                    guard current.operation == record.operation, current.value == record.value else {
                        throw FoundryImportError.corruptLevelDB("A key has conflicting records at the same sequence number.")
                    }
                    continue
                }
            }
            latest[record.key] = record
        }
        let activeRecords = latest.values
            .filter { $0.operation == .value }
            .sorted { $0.key < $1.key }
        guard activeRecords.count <= maximumDocumentCount else {
            throw FoundryImportError.tooManyDocuments(activeRecords.count)
        }

        var topDocuments: [String: (type: String, raw: FoundryJSONValue)] = [:]
        var embeddedItems: [String: [String: FoundryJSONValue]] = [:]
        var actorEffects: [String: [String: FoundryJSONValue]] = [:]
        var itemEffects: [String: [String: FoundryJSONValue]] = [:]
        var embeddedItemEffects: [String: [String: [String: FoundryJSONValue]]] = [:]
        var folders: [FoundryFolder] = []
        var unknownKeys: [String] = []

        for record in activeRecords {
            let raw: FoundryJSONValue
            do {
                raw = try FoundryJSONDecoding.decodeSource(record.value)
            } catch {
                throw FoundryImportError.invalidDocument(pack: pack.name, key: record.key)
            }
            if let id = record.key.suffix(after: "!items!") {
                topDocuments[id] = ("Item", raw)
            } else if let id = record.key.suffix(after: "!actors!") {
                topDocuments[id] = ("Actor", raw)
            } else if let suffix = record.key.suffix(after: "!actors.items.effects!"),
                      let parts = suffix.foundryIDComponents(expectedCount: 3) {
                embeddedItemEffects[parts[0], default: [:]][parts[1], default: [:]][parts[2]] = raw
            } else if let suffix = record.key.suffix(after: "!actors.items!"),
                      let parts = suffix.foundryIDComponents(expectedCount: 2) {
                embeddedItems[parts[0], default: [:]][parts[1]] = raw
            } else if let suffix = record.key.suffix(after: "!actors.effects!"),
                      let parts = suffix.foundryIDComponents(expectedCount: 2) {
                actorEffects[parts[0], default: [:]][parts[1]] = raw
            } else if let suffix = record.key.suffix(after: "!items.effects!"),
                      let parts = suffix.foundryIDComponents(expectedCount: 2) {
                itemEffects[parts[0], default: [:]][parts[1]] = raw
            } else if let id = record.key.suffix(after: "!folders!") {
                folders.append(decodeFolder(id: id, raw: raw))
            } else {
                unknownKeys.append(record.key)
            }
        }

        let rules = topDocuments.map { documentId, document in
            let canonicalId = FoundryCanonicalKey.topLevel(
                systemId: systemId,
                packName: pack.name,
                documentType: document.type,
                documentId: documentId
            )
            let actorEmbeddedEffects: [String: [String: FoundryJSONValue]] = embeddedItemEffects[documentId] ?? [:]
            var embedded: [FoundryEmbeddedRule] = []
            for (itemId, raw) in embeddedItems[documentId, default: [:]] {
                let embeddedId = FoundryCanonicalKey.embedded(parent: canonicalId, documentType: "Item", documentId: itemId)
                let rawItemEffects: [String: FoundryJSONValue] = actorEmbeddedEffects[itemId] ?? [:]
                let effects = decodeEffects(
                    rawItemEffects,
                    ownerCanonicalId: embeddedId
                )
                embedded.append(decodeEmbeddedRule(id: embeddedId, fallbackId: itemId, raw: raw, effects: effects))
            }
            embedded.sort { $0.name == $1.name ? $0.id < $1.id : $0.name < $1.name }
            let rawEffects = document.type == "Actor"
                ? actorEffects[documentId, default: [:]]
                : itemEffects[documentId, default: [:]]
            let effects = decodeEffects(rawEffects, ownerCanonicalId: canonicalId)
            return decodeRule(
                canonicalId: canonicalId,
                fallbackId: documentId,
                documentType: document.type,
                raw: document.raw,
                embeddedRules: embedded,
                effects: effects
            )
        }.sorted { lhs, rhs in
            let lhsSort = lhs.rawData["sort"]?.integerValue ?? 0
            let rhsSort = rhs.rawData["sort"]?.integerValue ?? 0
            if lhsSort != rhsSort { return lhsSort < rhsSort }
            if lhs.name != rhs.name { return lhs.name < rhs.name }
            return lhs.id < rhs.id
        }

        var diagnostics: [FoundryImportDiagnostic] = []
        if !unknownKeys.isEmpty {
            diagnostics.append(FoundryImportDiagnostic(
                severity: .warning,
                code: "unknown-leveldb-records",
                message: "Preserved the supported rules but skipped \(unknownKeys.count) unrecognized LevelDB records.",
                packName: pack.name
            ))
        }
        return Result(
            compendium: FoundryCompendium(
                manifest: pack,
                rules: rules,
                folders: folders.sorted { $0.name == $1.name ? $0.id < $1.id : $0.name < $1.name }
            ),
            diagnostics: diagnostics
        )
    }
}

private extension FoundryCompendiumDecoder {
    func decodeRule(
        canonicalId: String,
        fallbackId: String,
        documentType: String,
        raw: FoundryJSONValue,
        embeddedRules: [FoundryEmbeddedRule],
        effects: [FoundryRuleEffect]
    ) -> FoundryRuleDefinition {
        let documentId = raw["_id"]?.stringValue ?? fallbackId
        let subtype = raw["type"]?.stringValue ?? documentType.lowercased()
        let system = raw["system"] ?? .object([:])
        let description = system["description"]?.stringValue
        return FoundryRuleDefinition(
            id: canonicalId,
            documentId: documentId,
            packName: pack.name,
            documentType: documentType,
            subtype: subtype,
            category: FoundryRuleCategory.category(systemId: systemId, documentType: documentType, subtype: subtype),
            name: raw["name"]?.stringValue ?? documentId,
            descriptionHTML: description,
            imagePath: raw["img"]?.stringValue,
            folderId: raw["folder"]?.stringValue,
            values: flatten(system, path: ["system"]),
            tags: tags(documentType: documentType, subtype: subtype, system: system),
            references: FoundryReferenceDecoder.decode(in: raw),
            embeddedRules: embeddedRules,
            effects: effects,
            rawData: raw
        )
    }

    func decodeEmbeddedRule(
        id: String,
        fallbackId: String,
        raw: FoundryJSONValue,
        effects: [FoundryRuleEffect]
    ) -> FoundryEmbeddedRule {
        let documentId = raw["_id"]?.stringValue ?? fallbackId
        let subtype = raw["type"]?.stringValue ?? "item"
        return FoundryEmbeddedRule(
            id: id,
            name: raw["name"]?.stringValue ?? documentId,
            subtype: subtype,
            category: FoundryRuleCategory.category(systemId: systemId, documentType: "Item", subtype: subtype),
            descriptionHTML: raw.value(at: "system.description")?.stringValue,
            imagePath: raw["img"]?.stringValue,
            values: flatten(raw["system"] ?? .object([:]), path: ["system"]),
            references: FoundryReferenceDecoder.decode(in: raw),
            effects: effects,
            rawData: raw
        )
    }

    func decodeEffects(
        _ rawEffects: [String: FoundryJSONValue],
        ownerCanonicalId: String
    ) -> [FoundryRuleEffect] {
        rawEffects.map { fallbackId, raw in
            let effectId = raw["_id"]?.stringValue ?? fallbackId
            let canonicalId = FoundryCanonicalKey.embedded(
                parent: ownerCanonicalId,
                documentType: "ActiveEffect",
                documentId: effectId
            )
            let statuses = raw["statuses"]?.arrayValue?.compactMap(\.stringValue) ?? []
            let changes = raw["changes"]?.arrayValue?.compactMap { change -> FoundryRuleEffectChange? in
                guard let object = change.objectValue, let path = object["key"]?.stringValue else { return nil }
                return FoundryRuleEffectChange(
                    path: path,
                    mode: object["mode"]?.integerValue ?? 0,
                    operand: object["value"] ?? .null,
                    priority: object["priority"]?.integerValue
                )
            } ?? []
            return FoundryRuleEffect(
                id: canonicalId,
                name: raw["name"]?.stringValue ?? effectId,
                isDisabled: raw["disabled"]?.boolValue ?? false,
                transfersToActor: raw["transfer"]?.boolValue ?? false,
                statuses: statuses,
                changes: changes,
                duration: raw["duration"],
                rawData: raw
            )
        }.sorted { $0.name == $1.name ? $0.id < $1.id : $0.name < $1.name }
    }

    func decodeFolder(id: String, raw: FoundryJSONValue) -> FoundryFolder {
        FoundryFolder(
            id: raw["_id"]?.stringValue ?? id,
            name: raw["name"]?.stringValue ?? id,
            parentId: raw["folder"]?.stringValue,
            sort: raw["sort"]?.integerValue
        )
    }

    func tags(documentType: String, subtype: String, system: FoundryJSONValue) -> [String] {
        guard systemId == "ds4" else { return [] }
        var tags: [String] = []
        if subtype == "spell", let groups = system["spellGroups"]?.objectValue {
            tags.append(contentsOf: groups.compactMap { $0.value.boolValue == true ? $0.key : nil })
        }
        if documentType == "Actor" {
            if let type = system.value(at: "baseInfo.creatureType")?.stringValue, !type.isEmpty {
                tags.append("creatureType:\(type)")
            }
            if let size = system.value(at: "baseInfo.sizeCategory")?.stringValue, !size.isEmpty {
                tags.append("size:\(size)")
            }
        }
        return Array(Set(tags)).sorted()
    }
}

// MARK: - Canonical Identifiers

private enum FoundryCanonicalKey {
    static func topLevel(systemId: String, packName: String, documentType: String, documentId: String) -> String {
        "foundry://system/\(component(systemId))/pack/\(component(packName))/\(component(documentType))/\(component(documentId))"
    }

    static func embedded(parent: String, documentType: String, documentId: String) -> String {
        "\(parent)/\(component(documentType))/\(component(documentId))"
    }

    private static func component(_ value: String) -> String {
        FoundryPackagePath.encodedComponent(value)
    }
}
