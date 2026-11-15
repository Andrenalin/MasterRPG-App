// @copyright André Trettin

import Foundation

/// Applies the privacy choices made during Foundry preflight to every durable representation.
///
/// Foundry transports intentionally retain raw JSON beside normalized documents. Filtering only
/// the normalized document list would therefore leave private chat, user identifiers, or
/// ownership dictionaries in a second copy of the same data. This sanitizer treats the complete
/// package, including the RuleRPG payload, as one privacy boundary.
public enum FoundryVTTArchiveSanitizer {
    public static func sanitize(
        _ package: FoundryVTTImportPackage,
        includingChat: Bool,
        includingUsers: Bool
    ) -> FoundryVTTImportPackage {
        State(includingChat: includingChat, includingUsers: includingUsers).package(package)
    }
}

private struct State {
    let includingChat: Bool
    let includingUsers: Bool

    func package(_ package: FoundryVTTImportPackage) -> FoundryVTTImportPackage {
        let collections = package.collections.compactMap(collection)
        let documents = collections.flatMap(\.documents)
        let allDocuments = documents.flatMap(flatten)
        let documentCounts = Dictionary(grouping: allDocuments, by: { $0.documentType.rawValue })
            .mapValues(\.count)
        let statistics = FoundryVTTImportStatistics(
            collectionCount: collections.count,
            topLevelDocumentCount: documents.count,
            embeddedDocumentCount: allDocuments.count - documents.count,
            folderCount: collections.reduce(0) { $0 + $1.folders.count },
            unknownFieldCount: allDocuments.reduce(0) { $0 + $1.unknownFieldNames.count },
            documentCounts: documentCounts
        )
        return FoundryVTTImportPackage(
            formatVersion: package.formatVersion,
            sourceSHA256: package.sourceSHA256,
            kind: package.kind,
            manifestPath: package.manifestPath,
            manifest: package.manifest.map(manifest),
            collections: collections,
            resources: package.resources,
            textResources: package.textResources,
            diagnostics: package.diagnostics,
            statistics: statistics,
            rulePackage: package.rulePackage.map(rulePackage)
        )
    }

    func manifest(_ manifest: FoundryVTTPackageManifest) -> FoundryVTTPackageManifest {
        FoundryVTTPackageManifest(
            kind: manifest.kind,
            id: manifest.id,
            title: manifest.title,
            descriptionHTML: manifest.descriptionHTML,
            version: manifest.version,
            systemID: manifest.systemID,
            compatibility: manifest.compatibility,
            // A package author is licensing metadata rather than a Foundry User. Explicit nested
            // User or ChatMessage objects and private collection envelopes are still removed.
            rawData: sanitizeRaw(manifest.rawData, context: .manifestEnvelope) ?? .object([:])
        )
    }

    func collection(_ collection: FoundryDocumentCollection) -> FoundryDocumentCollection? {
        guard permits(collection.declaredDocumentType) else { return nil }
        let documents = collection.documents.compactMap(document)
        return FoundryDocumentCollection(
            id: collection.id,
            name: collection.name,
            label: collection.label,
            sourcePath: collection.sourcePath,
            declaredDocumentType: collection.declaredDocumentType,
            documents: documents,
            folders: collection.folders.filter { permits($0.documentType) }.map(folder),
            rawData: normalizedCollectionRawData(collection.rawData)
        )
    }

    func document(_ document: FoundryDocument) -> FoundryDocument? {
        guard permits(document.documentType) else { return nil }
        let embeddedDocuments = document.embeddedDocuments.compactMap(self.document)
        let sanitizedRaw = sanitizeRaw(document.rawData, context: .documentEnvelope) ?? .object([:])
        return FoundryDocument(
            id: document.id,
            documentID: document.documentID,
            documentType: document.documentType,
            subtype: document.subtype,
            name: document.name,
            folderID: document.folderID,
            sort: document.sort,
            imagePath: document.imagePath,
            descriptionHTML: document.descriptionHTML,
            parentID: document.parentID,
            sourceUUID: permittedReference(document.sourceUUID),
            sourceParentUUID: permittedReference(document.sourceParentUUID),
            embeddedDocuments: embeddedDocuments,
            references: document.references.filter(permittedReference),
            unknownFieldNames: document.unknownFieldNames.filter { !isDeniedMetadataKey($0) },
            rawData: removingRepresentedEmbeddedArrays(
                from: sanitizedRaw,
                parentType: document.documentType,
                representedDocuments: embeddedDocuments
            )
        )
    }

    func folder(_ folder: FoundryDocumentFolder) -> FoundryDocumentFolder {
        FoundryDocumentFolder(
            id: folder.id,
            documentID: folder.documentID,
            name: folder.name,
            parentID: folder.parentID,
            documentType: folder.documentType,
            sort: folder.sort,
            rawData: sanitizeRaw(folder.rawData, context: .documentEnvelope) ?? .object([:])
        )
    }

    func permits(_ type: FoundryDocumentType) -> Bool {
        if type == .chatMessage { return includingChat }
        if type == .user { return includingUsers }
        return true
    }

    func flatten(_ document: FoundryDocument) -> [FoundryDocument] {
        [document] + document.embeddedDocuments.flatMap(flatten)
    }
}

// MARK: - Raw JSON privacy and normalization

private extension State {
    static let identityKeys = Set([
        "author", "authorid", "createdby", "createdbyid", "modifiedby", "modifiedbyid",
        // Foundry v11+ writes the last editor into `_stats.lastModifiedBy`. See CODE_AUDIT_26 §6.2.
        "lastmodifiedby", "lastmodifiedbyid", "updatedby", "updatedbyid",
        "owner", "owners", "ownership",
        "permission", "permissions", "playerowner", "playerowners", "userid", "whisper",
    ])

    static let chatContainerKeys = Set(["chat", "chatmessage", "chatmessages", "messages"])
    static let userContainerKeys = Set(["user", "users"])

    /// Raw Foundry documents mix two different namespaces: Foundry's document metadata and the
    /// game system's own schema below `system`. Words such as `user` and `messages` are valid rule
    /// field names, so only document/manifest contexts are privacy-filtered by key. Semantic rule
    /// payloads are retained byte-for-byte at the JSON-value level.
    enum RawPrivacyContext {
        case manifestEnvelope
        case manifestPayload
        case documentEnvelope
        case documentPayload
        case semantic

        var scrubsIdentityKeys: Bool {
            self == .documentEnvelope || self == .documentPayload
        }

        var scrubsPrivateContainers: Bool {
            self == .manifestEnvelope || self == .documentEnvelope
        }

        var detectsPrivateDocuments: Bool { self != .semantic }

        func child(named normalizedKey: String) -> Self {
            if self == .semantic || ["flags", "system"].contains(normalizedKey) {
                return .semantic
            }
            switch self {
            case .manifestEnvelope, .manifestPayload:
                return .manifestPayload
            case .documentEnvelope, .documentPayload:
                return .documentPayload
            case .semantic:
                return .semantic
            }
        }
    }

    func sanitizeRaw(
        _ value: FoundryJSONValue,
        context: RawPrivacyContext
    ) -> FoundryJSONValue? {
        switch value {
        case .object(let object):
            guard !context.detectsPrivateDocuments || !isDeniedDocumentObject(object) else {
                return nil
            }
            var sanitized: [String: FoundryJSONValue] = [:]
            for key in object.keys.sorted() {
                let normalizedKey = normalizedKey(key)
                if context.scrubsPrivateContainers,
                   !includingChat,
                   Self.chatContainerKeys.contains(normalizedKey) {
                    continue
                }
                if context.scrubsPrivateContainers,
                   !includingUsers,
                   Self.userContainerKeys.contains(normalizedKey) {
                    continue
                }
                if context.scrubsIdentityKeys,
                   !includingUsers,
                   Self.identityKeys.contains(normalizedKey) {
                    continue
                }
                guard let child = object[key],
                      let sanitizedChild = sanitizeRaw(
                        child,
                        context: context.child(named: normalizedKey)
                      ) else { continue }
                sanitized[key] = sanitizedChild
            }
            return .object(sanitized)
        case .array(let array):
            return .array(array.compactMap {
                sanitizeRaw($0, context: context)
            })
        default:
            return value
        }
    }

    func isDeniedDocumentObject(_ object: [String: FoundryJSONValue]) -> Bool {
        let declaredTypes = [
            object["documentName"]?.stringValue,
            object["documentType"]?.stringValue,
            object["_stats"]?.objectValue?["documentName"]?.stringValue,
        ].compactMap { $0 }
        if declaredTypes.contains(where: isDeniedDocumentTypeName) { return true }
        let identifiers = [
            object["_key"]?.stringValue,
            object["uuid"]?.stringValue,
            object["sourceUUID"]?.stringValue,
        ].compactMap { $0 }
        return identifiers.contains(where: isDeniedReference)
    }

    func normalizedCollectionRawData(_ rawData: FoundryJSONValue?) -> FoundryJSONValue? {
        guard let rawData,
              let sanitized = sanitizeRaw(rawData, context: .documentEnvelope) else { return nil }
        // The reader has already normalized these full source arrays into `documents`. Keeping a
        // second copy makes privacy filtering fragile and roughly doubles large JSON exports.
        if case .array = sanitized { return nil }
        guard case .object(var object) = sanitized,
              object["documents"]?.arrayValue != nil else { return sanitized }
        object.removeValue(forKey: "documents")
        return object.isEmpty ? nil : .object(object)
    }

    func removingRepresentedEmbeddedArrays(
        from rawData: FoundryJSONValue,
        parentType: FoundryDocumentType,
        representedDocuments: [FoundryDocument]
    ) -> FoundryJSONValue {
        guard case .object(var object) = rawData,
              let mappings = Self.embeddedMappings[parentType] else { return rawData }
        for (key, type) in mappings {
            let representedIDs = Set(
                representedDocuments.lazy
                    .filter { $0.documentType == type }
                    .map(\.documentID)
            )
            guard !representedIDs.isEmpty,
                  case .array(let values) = object[key] else { continue }
            let remainder = values.filter { !representsDocument($0, ids: representedIDs) }
            if remainder.isEmpty {
                object.removeValue(forKey: key)
            } else {
                object[key] = .array(remainder)
            }
        }
        return .object(object)
    }

    func representsDocument(_ raw: FoundryJSONValue, ids: Set<String>) -> Bool {
        guard case .object(let object) = raw else { return false }
        let id = object["_id"]?.stringValue ?? object["id"]?.stringValue
        return id.map(ids.contains) ?? false
    }

    static let embeddedMappings: [FoundryDocumentType: [String: FoundryDocumentType]] = [
        .actor: ["items": .item, "effects": .activeEffect],
        .item: ["effects": .activeEffect],
        .scene: [
            "levels": .level, "tokens": .token, "walls": .wall, "lights": .ambientLight,
            "sounds": .ambientSound, "tiles": .tile, "drawings": .drawing,
            "notes": .note, "regions": .region,
        ],
        .journalEntry: ["pages": .journalEntryPage],
        .rollTable: ["results": .tableResult],
        .playlist: ["sounds": .playlistSound],
        .cards: ["cards": .card],
        .combat: ["combatants": .combatant],
        .adventure: [
            "actors": .actor, "items": .item, "scenes": .scene,
            "journal": .journalEntry, "journals": .journalEntry,
            "journalEntries": .journalEntry, "tables": .rollTable,
            "rollTables": .rollTable, "playlists": .playlist, "cards": .cards,
            "combats": .combat, "macros": .macro, "folders": .folder,
        ],
    ]
}

// MARK: - RuleRPG hand-off payload

private extension State {
    func rulePackage(_ package: FoundryRulePackage) -> FoundryRulePackage {
        FoundryRulePackage(
            formatVersion: package.formatVersion,
            sourceSHA256: package.sourceSHA256,
            manifest: FoundrySystemManifest(
                id: package.manifest.id,
                title: package.manifest.title,
                description: package.manifest.description,
                version: package.manifest.version,
                compatibility: package.manifest.compatibility,
                packs: package.manifest.packs.filter {
                    !isDeniedDocumentTypeName($0.documentType)
                },
                rawData: sanitizeRaw(package.manifest.rawData, context: .manifestEnvelope)
                    ?? .object([:])
            ),
            manifestPath: package.manifestPath,
            templatePath: package.templatePath,
            templateData: package.templateData.flatMap {
                sanitizeRaw($0, context: .semantic)
            },
            schemas: package.schemas.compactMap(schema),
            compendiums: package.compendiums.compactMap(compendium),
            localizations: package.localizations.map { localization in
                FoundryLocalizationCatalog(
                    languageCode: localization.languageCode,
                    name: localization.name,
                    path: localization.path,
                    translations: sanitizeRaw(localization.translations, context: .semantic)
                        ?? .object([:])
                )
            },
            assetPaths: package.assetPaths,
            resources: package.resources,
            licensePaths: package.licensePaths,
            licenseDocuments: package.licenseDocuments,
            diagnostics: package.diagnostics
        )
    }

    func schema(_ schema: FoundryRuleSchema) -> FoundryRuleSchema? {
        guard !isDeniedDocumentTypeName(schema.documentType) else { return nil }
        return FoundryRuleSchema(
            documentType: schema.documentType,
            subtype: schema.subtype,
            inheritedTemplates: schema.inheritedTemplates,
            fields: schema.fields.compactMap { field in
                guard !isDeniedMetadataPath(field.path) else { return nil }
                return FoundryRuleField(
                    path: field.path,
                    valueKind: field.valueKind,
                    defaultValue: sanitizeRaw(field.defaultValue, context: .semantic) ?? .null
                )
            },
            rawData: sanitizeRaw(schema.rawData, context: .semantic) ?? .object([:])
        )
    }

    func compendium(_ compendium: FoundryCompendium) -> FoundryCompendium? {
        guard !isDeniedDocumentTypeName(compendium.manifest.documentType) else { return nil }
        return FoundryCompendium(
            manifest: compendium.manifest,
            rules: compendium.rules.compactMap(rule),
            folders: compendium.folders
        )
    }

    func rule(_ rule: FoundryRuleDefinition) -> FoundryRuleDefinition? {
        guard !isDeniedDocumentTypeName(rule.documentType) else { return nil }
        return FoundryRuleDefinition(
            id: rule.id,
            documentID: rule.documentID,
            packName: rule.packName,
            documentType: rule.documentType,
            subtype: rule.subtype,
            category: rule.category,
            name: rule.name,
            descriptionHTML: rule.descriptionHTML,
            imagePath: rule.imagePath,
            folderID: rule.folderID,
            values: rule.values.compactMap(ruleValue),
            tags: rule.tags,
            references: rule.references.filter(permittedReference),
            embeddedRules: rule.embeddedRules.compactMap(embeddedRule),
            effects: rule.effects.map(effect),
            rawData: sanitizeRaw(rule.rawData, context: .documentEnvelope) ?? .object([:])
        )
    }

    func embeddedRule(_ rule: FoundryEmbeddedRule) -> FoundryEmbeddedRule? {
        return FoundryEmbeddedRule(
            id: rule.id,
            name: rule.name,
            subtype: rule.subtype,
            category: rule.category,
            descriptionHTML: rule.descriptionHTML,
            imagePath: rule.imagePath,
            values: rule.values.compactMap(ruleValue),
            references: rule.references.filter(permittedReference),
            effects: rule.effects.map(effect),
            rawData: sanitizeRaw(rule.rawData, context: .documentEnvelope) ?? .object([:])
        )
    }

    func ruleValue(_ value: FoundryRuleValue) -> FoundryRuleValue? {
        guard !isDeniedMetadataPath(value.path),
              let sanitized = sanitizeRaw(value.value, context: .semantic) else { return nil }
        return FoundryRuleValue(path: value.path, value: sanitized)
    }

    func effect(_ effect: FoundryRuleEffect) -> FoundryRuleEffect {
        FoundryRuleEffect(
            id: effect.id,
            name: effect.name,
            isDisabled: effect.isDisabled,
            transfersToActor: effect.transfersToActor,
            statuses: effect.statuses,
            changes: effect.changes.compactMap { change in
                guard !isDeniedMetadataPath(change.path),
                      let operand = sanitizeRaw(
                        change.operand,
                        context: .semantic
                      ) else { return nil }
                return FoundryRuleEffectChange(
                    path: change.path,
                    mode: change.mode,
                    operand: operand,
                    priority: change.priority
                )
            },
            duration: effect.duration.flatMap {
                sanitizeRaw($0, context: .semantic)
            },
            rawData: sanitizeRaw(effect.rawData, context: .documentEnvelope) ?? .object([:])
        )
    }
}

// MARK: - Privacy predicates

private extension State {
    func normalizedKey(_ key: String) -> String {
        key.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    func isDeniedMetadataKey(_ key: String) -> Bool {
        guard !includingUsers else { return false }
        let normalized = normalizedKey(key)
        return Self.identityKeys.contains(normalized) || Self.userContainerKeys.contains(normalized)
    }

    func isDeniedMetadataPath(_ path: String) -> Bool {
        let components = path.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        if let first = components.first,
           ["flags", "system"].contains(normalizedKey(first)) {
            return false
        }
        return components.contains(where: isDeniedMetadataKey)
    }

    func isDeniedDocumentTypeName(_ name: String) -> Bool {
        let normalized = normalizedKey(name)
        if !includingChat, ["chatmessage", "chatmessages"].contains(normalized) {
            return true
        }
        return !includingUsers && ["user", "users"].contains(normalized)
    }

    func isDeniedReference(_ value: String) -> Bool {
        let normalized = value.lowercased()
        if !includingChat,
           normalized.hasPrefix("chatmessage.")
            || normalized.contains("/chatmessage/")
            || normalized.contains("!chatmessages!") {
            return true
        }
        return !includingUsers
            && (normalized.hasPrefix("user.")
                || normalized.contains("/user/")
                || normalized.contains("!users!"))
    }

    func permittedReference(_ value: String?) -> String? {
        value.flatMap { isDeniedReference($0) ? nil : $0 }
    }

    func permittedReference(_ reference: FoundryRuleReference) -> Bool {
        !isDeniedReference(reference.target)
            && !isDeniedReference(reference.rawToken)
            && !isDeniedReference(reference.documentID ?? "")
    }
}
