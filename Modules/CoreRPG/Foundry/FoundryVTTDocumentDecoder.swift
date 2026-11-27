// @copyright André Trettin

import CryptoKit
import Foundation

// The document tree decoding and LevelDB keys, split out of FoundryVTTImportReader.swift. See CODE_AUDIT_29 §9.9.

struct FoundryVTTDocumentDecoder {
    /// How deep embedded documents may nest before the document is refused. See CODE_AUDIT_29 §9.8.
    static let maximumEmbeddedDepth = 64

    let packageKind: FoundryVTTPackageKind
    let packageId: String
    let spec: FoundryVTTCollectionSpec
    let limits: FoundryImportLimits

    func decodeLevelDB(
        _ records: [FoundryLevelDBRecord],
        budget: inout FoundryVTTReadBudget
    ) throws -> (collection: FoundryDocumentCollection, diagnostics: [FoundryImportDiagnostic]) {
        var rawByPath: [[FoundryVTTRecordComponent]: FoundryJSONValue] = [:]
        var folderRaws: [(String, FoundryJSONValue)] = []
        var invalidKeys: [String] = []
        for record in records {
            try Task.checkCancellation()
            guard let path = FoundryVTTLevelDBKey.parse(record.key), !path.isEmpty else {
                invalidKeys.append(record.key)
                continue
            }
            do {
                let raw = try FoundryJSONDecoding.decode(record.value, context: record.key)
                if path.count == 1, path[0].documentType == .folder {
                    folderRaws.append((path[0].id, raw))
                } else {
                    rawByPath[path] = raw
                }
            } catch {
                invalidKeys.append(record.key)
            }
        }

        var childrenByParent: [[FoundryVTTRecordComponent]: [[FoundryVTTRecordComponent]]] = [:]
        for path in rawByPath.keys where path.count > 1 {
            childrenByParent[Array(path.dropLast()), default: []].append(path)
        }
        let topPaths = rawByPath.keys.filter { $0.count == 1 }.sorted(by: FoundryVTTLevelDBKey.lessThan)
        var documents: [FoundryDocument] = []
        for path in topPaths {
            guard let raw = rawByPath[path] else { continue }
            documents.append(try decodeDocument(
                raw: raw,
                fallbackId: path.last?.id ?? "document",
                explicitType: path.last?.documentType ?? spec.declaredType,
                parentCanonicalId: nil,
                externalPath: path,
                rawByPath: rawByPath,
                childrenByParent: childrenByParent,
                depth: 0,
                budget: &budget
            ))
        }
        var folders = folderRaws.map { pair in
            decodeFolder(fallbackId: pair.0, raw: pair.1)
        }
        folders.sort { lhs, rhs in
            lhs.name == rhs.name ? lhs.id < rhs.id : lhs.name < rhs.name
        }
        let diagnostics = invalidKeys.isEmpty ? [] : [FoundryImportDiagnostic(
            severity: .warning,
            code: "unrecognized-leveldb-records",
            message: "Skipped \(invalidKeys.count) LevelDB records whose key hierarchy or JSON value was invalid.",
            packName: spec.name
        )]
        return (makeCollection(documents: documents, folders: folders), diagnostics)
    }

    func decodeRawDocuments(
        _ raws: [(String, FoundryJSONValue)],
        budget: inout FoundryVTTReadBudget
    ) throws -> (collection: FoundryDocumentCollection, diagnostics: [FoundryImportDiagnostic]) {
        var documents: [FoundryDocument] = []
        var folders: [FoundryDocumentFolder] = []
        var invalidCount = 0
        for (fallbackId, raw) in raws.sorted(by: { $0.0 < $1.0 }) {
            guard raw.objectValue != nil else {
                invalidCount += 1
                continue
            }
            let inferredType = FoundryDocumentType.inferred(from: raw, fallback: spec.declaredType)
            if inferredType == .folder {
                folders.append(decodeFolder(fallbackId: fallbackId, raw: raw))
            } else {
                documents.append(try decodeDocument(
                    raw: raw,
                    fallbackId: fallbackId,
                    explicitType: inferredType,
                    parentCanonicalId: nil,
                    externalPath: nil,
                    rawByPath: [:],
                    childrenByParent: [:],
                    depth: 0,
                    budget: &budget
                ))
            }
        }
        let diagnostics = invalidCount == 0 ? [] : [FoundryImportDiagnostic(
            severity: .warning,
            code: "invalid-json-documents",
            message: "Skipped \(invalidCount) non-object values in \(spec.name).",
            packName: spec.name
        )]
        return (makeCollection(documents: documents, folders: folders), diagnostics)
    }
}

extension FoundryVTTDocumentDecoder {
    func makeCollection(
        documents: [FoundryDocument],
        folders: [FoundryDocumentFolder]
    ) -> FoundryDocumentCollection {
        FoundryDocumentCollection(
            id: spec.id,
            name: spec.name,
            label: spec.label,
            sourcePath: spec.path,
            declaredDocumentType: spec.declaredType,
            documents: documents.sorted(by: FoundryDocument.foundrySort),
            folders: folders.sorted { lhs, rhs in lhs.name == rhs.name ? lhs.id < rhs.id : lhs.name < rhs.name },
            rawData: spec.rawData
        )
    }

    func decodeFolder(fallbackId: String, raw: FoundryJSONValue) -> FoundryDocumentFolder {
        let documentId = raw["_id"]?.stringValue ?? raw["id"]?.stringValue ?? fallbackId
        return FoundryDocumentFolder(
            id: canonicalTopLevelId(type: .folder, documentId: documentId),
            documentId: documentId,
            name: raw["name"]?.stringValue ?? documentId,
            parentId: raw["folder"]?.foundryIdentifier ?? raw["parent"]?.foundryIdentifier,
            documentType: .inferred(from: raw["type"]?.stringValue),
            sort: raw["sort"]?.integerValue,
            rawData: raw
        )
    }

    private func decodeDocument(
        raw: FoundryJSONValue,
        fallbackId: String,
        explicitType: FoundryDocumentType,
        parentCanonicalId: String?,
        externalPath: [FoundryVTTRecordComponent]?,
        rawByPath: [[FoundryVTTRecordComponent]: FoundryJSONValue],
        childrenByParent: [[FoundryVTTRecordComponent]: [[FoundryVTTRecordComponent]]],
        depth: Int,
        budget: inout FoundryVTTReadBudget
    ) throws -> FoundryDocument {
        guard depth < Self.maximumEmbeddedDepth else {
            throw FoundryImportError.invalidDocument(pack: spec.name, key: "embedded hierarchy exceeds \(Self.maximumEmbeddedDepth) levels")
        }
        try budget.includeRecord(limits: limits)
        let documentId = raw["_id"]?.stringValue ?? raw["id"]?.stringValue ?? fallbackId
        let type = explicitType == .unknown
            ? FoundryDocumentType.inferred(from: raw, fallback: spec.declaredType)
            : explicitType
        let canonicalId = parentCanonicalId.map {
            "\($0)/\(Self.component(type.rawValue))/\(Self.component(documentId))"
        } ?? canonicalTopLevelId(type: type, documentId: documentId)

        var embedded: [FoundryDocument] = []
        var externalIdentities = Set<String>()
        if let externalPath {
            for childPath in (childrenByParent[externalPath] ?? []).sorted(by: FoundryVTTLevelDBKey.lessThan) {
                guard let component = childPath.last, let childRaw = rawByPath[childPath] else { continue }
                externalIdentities.insert("\(component.documentType.rawValue):\(component.id)")
                embedded.append(try decodeDocument(
                    raw: childRaw,
                    fallbackId: component.id,
                    explicitType: component.documentType,
                    parentCanonicalId: canonicalId,
                    externalPath: childPath,
                    rawByPath: rawByPath,
                    childrenByParent: childrenByParent,
                    depth: depth + 1,
                    budget: &budget
                ))
            }
        }
        let candidates = FoundryVTTEmbeddedExtractor.documents(in: raw, parentType: type)
        // A positional fallback id must not equal a sibling's real id: the identity validator
        // then failed the whole package. The usual id is kept (re-imports update the same
        // records); only a collision gets a suffix. See CODE_AUDIT_29 §5.26.
        var takenIds = Set(candidates.compactMap { candidate in
            candidate.raw["_id"]?.stringValue ?? candidate.raw["id"]?.stringValue
        })
        for candidate in candidates {
            let candidateId: String
            if let realId = candidate.raw["_id"]?.stringValue ?? candidate.raw["id"]?.stringValue {
                candidateId = realId
            } else {
                var fallback = "embedded-\(embedded.count + 1)"
                var suffix = 1
                while takenIds.contains(fallback) {
                    suffix += 1
                    fallback = "embedded-\(embedded.count + 1)-\(suffix)"
                }
                takenIds.insert(fallback)
                candidateId = fallback
            }
            guard !externalIdentities.contains("\(candidate.type.rawValue):\(candidateId)") else { continue }
            embedded.append(try decodeDocument(
                raw: candidate.raw,
                fallbackId: candidateId,
                explicitType: candidate.type,
                parentCanonicalId: canonicalId,
                externalPath: nil,
                rawByPath: [:],
                childrenByParent: [:],
                depth: depth + 1,
                budget: &budget
            ))
        }

        let knownFields = FoundryVTTKnownFields.names(for: type)
        let unknownFields = raw.objectValue?.keys.filter { !knownFields.contains($0) }.sorted() ?? []
        return FoundryDocument(
            id: canonicalId,
            documentId: documentId,
            documentType: type,
            subtype: raw["type"]?.stringValue.flatMap {
                FoundryDocumentType.inferred(from: $0) == .unknown ? $0 : nil
            },
            name: raw["name"]?.stringValue ?? documentId,
            folderId: raw["folder"]?.foundryIdentifier,
            sort: raw["sort"]?.integerValue,
            imagePath: raw["img"]?.stringValue ?? raw["image"]?.stringValue ?? raw.value(at: "texture.src")?.stringValue,
            descriptionHTML: FoundryVTTDescriptionFinder.description(in: raw),
            parentId: parentCanonicalId,
            embeddedDocuments: embedded.sorted(by: FoundryDocument.foundrySort),
            references: FoundryReferenceDecoder.decode(in: raw),
            unknownFieldNames: unknownFields,
            rawData: raw
        )
    }

    func canonicalTopLevelId(type: FoundryDocumentType, documentId: String) -> String {
        "foundry://\(packageKind.rawValue)/\(Self.component(packageId))/collection/\(Self.component(spec.id))/\(Self.component(type.rawValue))/\(Self.component(documentId))"
    }

    static func component(_ value: String) -> String {
        FoundryPackagePath.encodedComponent(value)
    }
}

private enum FoundryVTTLevelDBKey {
    static func parse(_ key: String) -> [FoundryVTTRecordComponent]? {
        guard key.hasPrefix("!"),
              let namespaceEnd = key.dropFirst().firstIndex(of: "!") else { return nil }
        let namespace = key[key.index(after: key.startIndex)..<namespaceEnd]
        let identifiersStart = key.index(after: namespaceEnd)
        let identifiers = key[identifiersStart...]
        let collections = namespace.split(separator: ".").map(String.init)
        let ids = identifiers.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard !collections.isEmpty, collections.count == ids.count,
              ids.allSatisfy({ !$0.isEmpty }) else { return nil }
        var result: [FoundryVTTRecordComponent] = []
        for (collection, id) in zip(collections, ids) {
            let parentType = result.last?.documentType
            let type = FoundryDocumentType.inferred(
                fromCollectionName: collection,
                embeddedIn: parentType
            )
            result.append(FoundryVTTRecordComponent(collection: collection, id: id, documentType: type))
        }
        return result
    }

    static func lessThan(
        _ lhs: [FoundryVTTRecordComponent],
        _ rhs: [FoundryVTTRecordComponent]
    ) -> Bool {
        let left = lhs.map { "\($0.collection):\($0.id)" }.joined(separator: "/")
        let right = rhs.map { "\($0.collection):\($0.id)" }.joined(separator: "/")
        return left < right
    }
}

private enum FoundryVTTEmbeddedExtractor {
    struct Candidate {
        let type: FoundryDocumentType
        let raw: FoundryJSONValue
    }

    static func documents(in raw: FoundryJSONValue, parentType: FoundryDocumentType) -> [Candidate] {
        guard let object = raw.objectValue else { return [] }
        let mappings = FoundryEmbeddedMappings.mappings(for: parentType)
        var result: [Candidate] = []
        for key in mappings.keys.sorted() {
            guard let values = object[key]?.arrayValue, let type = mappings[key] else { continue }
            for value in values where value.objectValue != nil {
                result.append(Candidate(type: type, raw: value))
            }
        }
        return result
    }
}

private enum FoundryVTTKnownFields {
    static let base = Set([
        "_id", "id", "_key", "_stats", "name", "type", "documentName", "documentType",
        "folder", "sort", "ownership", "permission", "flags", "system", "img", "image",
        "description", "content", "text", "effects",
    ])

    static func names(for type: FoundryDocumentType) -> Set<String> {
        base.union(typeFields[type] ?? [])
    }

    static let typeFields: [FoundryDocumentType: Set<String>] = [
        .actor: ["items", "prototypeToken"],
        .item: ["effects"],
        .scene: [
            "active", "navigation", "navOrder", "background", "foreground", "thumb",
            "width", "height", "padding", "initial", "initialLevel", "backgroundColor", "grid", "tokenVision",
            "fog", "fogExploration", "globalLight", "globalLightThreshold", "darkness",
            "environment", "weather", "levels", "tokens", "walls", "lights", "sounds", "tiles",
            "drawings", "notes", "regions", "playlist", "playlistSound",
        ],
        .level: [
            "background", "elevation", "fog", "foreground", "textures", "visibility",
            "tokens", "walls", "lights", "sounds", "tiles", "drawings", "notes", "regions",
        ],
        .journalEntry: ["pages"],
        .journalEntryPage: ["title", "src", "video", "image", "text"],
        .rollTable: ["formula", "replacement", "displayRoll", "results"],
        .tableResult: ["range", "drawn", "weight", "documentCollection", "documentId"],
        .playlist: ["mode", "playing", "fade", "seed", "sounds"],
        .playlistSound: ["path", "volume", "repeat", "channel", "playing", "pausedTime"],
        .cards: ["cards", "displayCount", "pile", "hands", "drawn"],
        .card: ["faces", "back", "face", "drawn", "origin"],
        .adventure: [
            "actors", "items", "scenes", "journal", "journals", "journalEntries", "tables",
            "rollTables", "playlists", "cards", "combats", "macros", "folders",
        ],
        .combat: ["scene", "active", "round", "turn", "combatants"],
        .folder: ["parent", "sorting", "color"],
    ]
}

private enum FoundryVTTDescriptionFinder {
    static func description(in raw: FoundryJSONValue) -> String? {
        let candidates = [
            raw.value(at: "text.content"), raw["content"],
            raw.value(at: "system.description.value"), raw.value(at: "system.description"),
            raw["description"],
        ]
        return candidates.compactMap { $0?.stringValue }.first
    }
}

private extension FoundryDocument {
    static func foundrySort(_ lhs: Self, _ rhs: Self) -> Bool {
        let leftSort = lhs.sort ?? 0
        let rightSort = rhs.sort ?? 0
        if leftSort != rightSort { return leftSort < rightSort }
        if lhs.name != rhs.name { return lhs.name < rhs.name }
        return lhs.id < rhs.id
    }
}

extension FoundryJSONValue {
    var foundryScalarString: String? {
        switch self {
        case .string(let value): value
        case .integer(let value): String(value)
        case .unsignedInteger(let value): String(value)
        case .number(let value): String(value)
        default: nil
        }
    }

    var foundryIdentifier: String? {
        stringValue ?? self["_id"]?.stringValue ?? self["id"]?.stringValue
    }
}

extension Data.SubSequence {
    func foundryTrimmingASCIIWhitespace() -> Self {
        var lower = startIndex
        var upper = endIndex
        while lower < upper, [0x20, 0x09, 0x0d].contains(self[lower]) { formIndex(after: &lower) }
        while lower < upper {
            let previous = index(before: upper)
            guard [0x20, 0x09, 0x0d].contains(self[previous]) else { break }
            upper = previous
        }
        return self[lower..<upper]
    }
}

enum FoundryVTTDocumentIdentityValidator {
    static func validate(_ collections: [FoundryDocumentCollection]) throws {
        var sourceByCanonicalId: [String: String] = [:]

        func visit(_ document: FoundryDocument, collection: FoundryDocumentCollection) throws {
            if let firstSource = sourceByCanonicalId[document.id] {
                throw FoundryImportError.invalidDocument(
                    pack: collection.name,
                    key: "duplicate canonical identifier \(document.id) (already present in \(firstSource))"
                )
            }
            sourceByCanonicalId[document.id] = collection.name
            for child in document.embeddedDocuments {
                try visit(child, collection: collection)
            }
        }

        for collection in collections {
            for document in collection.documents {
                try visit(document, collection: collection)
            }
        }
    }
}

enum FoundryVTTStatisticsBuilder {
    static func build(_ collections: [FoundryDocumentCollection]) -> FoundryVTTImportStatistics {
        var embeddedCount = 0
        var unknownFieldCount = 0
        var counts: [String: Int] = [:]
        func visit(_ document: FoundryDocument, isTopLevel: Bool) {
            counts[document.documentType.rawValue, default: 0] += 1
            unknownFieldCount += document.unknownFieldNames.count
            if !isTopLevel { embeddedCount += 1 }
            for child in document.embeddedDocuments { visit(child, isTopLevel: false) }
        }
        for document in collections.flatMap(\.documents) { visit(document, isTopLevel: true) }
        return FoundryVTTImportStatistics(
            collectionCount: collections.count,
            topLevelDocumentCount: collections.reduce(0) { $0 + $1.documents.count },
            embeddedDocumentCount: embeddedCount,
            folderCount: collections.reduce(0) { $0 + $1.folders.count },
            unknownFieldCount: unknownFieldCount,
            documentCounts: counts
        )
    }
}
