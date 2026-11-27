// @copyright André Trettin

import Foundation

// Extracted from FoundryVTTImportReader.swift per CODE_AUDIT §9.8 — the `.mrpgfoundry` bridge
// export format's own decoder, distinct from the LevelDB-origin format
// (`FoundryVTTDecoder+CollectionDecoding.swift`). Despite decoding a completely different wire
// format, this still shares several types with the LevelDB path (`FoundryVTTDataSource`,
// `FoundryVTTReadBudget`, `FoundryVTTCollectionSpec`, `FoundryVTTDocumentDecoder`,
// `FoundryVTTStatisticsBuilder`, `FoundryVTTDocumentIdentityValidator`) — those stay in the main
// file since they're genuinely shared infrastructure, not bridge-specific.

// MARK: - Foundry Bridge Decoding

struct FoundryBridgeDecoder {
    let limits: FoundryImportLimits

    func decodePackage(source: FoundryVTTDataSource) throws -> FoundryVTTImportPackage {
        guard let selectedPath = source.selectedPath,
              let data = try source.data(forPath: selectedPath) else {
            throw FoundryImportError.unsupportedSource
        }
        // Before the decode and hash, not after: an oversized file must not be read in full first.
        // See CODE_AUDIT_26 §5.60.
        guard data.count <= limits.maximumRuleDataSize else { throw FoundryImportError.fileTooLarge(data.count) }
        let contents = try decodeContents(data, retainingAssetPaths: [])
        let header = contents.header
        guard let sourceObject = header["source"]?.objectValue else {
            throw FoundryImportError.invalidManifest("The bridge source declaration is missing.")
        }
        let sourceKind = sourceObject["kind"]?.stringValue ?? "selection"
        let kind: FoundryVTTPackageKind = switch sourceKind {
        case "world": .world
        case "adventure": .documentCollection
        default: .exportedDocument
        }
        let packageId = sourceObject["id"]?.stringValue ?? "foundry-export"
        let title = sourceObject["title"]?.stringValue ?? packageId
        let manifest = FoundryVTTPackageManifest(
            kind: kind,
            id: packageId,
            title: title,
            descriptionHTML: nil,
            version: sourceObject["systemVersion"]?.foundryScalarString,
            systemId: sourceObject["systemID"]?.stringValue,
            compatibility: FoundryCompatibility(
                minimum: nil,
                verified: header["foundryVersion"]?.foundryScalarString,
                maximum: nil
            ),
            rawData: .object(header)
        )

        var grouped: [FoundryBridgeGroupKey: [FoundryBridgeDocumentRecord]] = [:]
        for record in contents.documents {
            grouped[FoundryBridgeGroupKey(collection: record.collection, documentType: record.documentType), default: []]
                .append(record)
        }
        var budget = FoundryVTTReadBudget(encodedBytes: data.count, decodedBytes: data.count, recordCount: 0)
        var collections: [FoundryDocumentCollection] = []
        var diagnostics = contents.diagnostics
        for groupKey in grouped.keys.sorted(by: {
            $0.collection == $1.collection
                ? $0.documentType.rawValue < $1.documentType.rawValue
                : $0.collection < $1.collection
        }) {
            guard let records = grouped[groupKey] else { continue }
            let declared = groupKey.documentType != .unknown
                ? groupKey.documentType
                : .inferred(fromCollectionName: groupKey.collection)
            let spec = FoundryVTTCollectionSpec(
                id: "bridge:\(groupKey.collection):\(declared.rawValue)",
                name: groupKey.collection,
                label: groupKey.collection,
                path: selectedPath,
                declaredType: declared,
                rawData: nil
            )
            let rawDocuments = records.enumerated().map { index, record in
                let fallback = record.data["_id"]?.stringValue
                    ?? record.uuid.split(separator: ".").last.map(String.init)
                    ?? "document-\(index + 1)"
                return (fallback, record.data)
            }
            let result = try FoundryVTTDocumentDecoder(
                packageKind: kind,
                packageId: packageId,
                spec: spec,
                limits: limits
            ).decodeRawDocuments(rawDocuments, budget: &budget)
            let recordsById = Dictionary(records.map { record in
                let id = record.data["_id"]?.stringValue
                    ?? record.uuid.split(separator: ".").last.map(String.init)
                    ?? record.uuid
                return (id, record)
            }, uniquingKeysWith: { first, _ in first })
            let documents = result.collection.documents.map { document in
                guard let record = recordsById[document.documentId] else { return document }
                return document.withBridgeSource(uuid: record.uuid, parentUUID: record.parentUUID)
            }
            collections.append(FoundryDocumentCollection(
                id: result.collection.id,
                name: result.collection.name,
                label: result.collection.label,
                sourcePath: result.collection.sourcePath,
                declaredDocumentType: result.collection.declaredDocumentType,
                documents: documents,
                folders: result.collection.folders,
                rawData: result.collection.rawData
            ))
            diagnostics.append(contentsOf: result.diagnostics)
        }

        var resources = contents.assetMetadata.map { path, metadata in
            FoundryPackageResource(
                logicalPath: path,
                packagePath: "bridge-assets/\(path)",
                location: .packaged,
                byteCount: metadata.byteCount,
                sha256: metadata.sha256
            )
        }
        for reference in contents.assetReferences where !contents.assetMetadata.keys.contains(reference.path) {
            let location: FoundryPackageResource.Location = switch reference.status {
            case "remote": .remote
            case "core", "external": .foundryInstallation
            default: .unresolved
            }
            resources.append(FoundryPackageResource(
                logicalPath: reference.path,
                packagePath: nil,
                location: location,
                byteCount: nil,
                sha256: nil
            ))
        }
        var representedPaths = Set(resources.map(\.logicalPath))
        let referencedPaths = FoundryAssetPathCollector.paths(in: collections.flatMap(\.documents).map(\.rawData))
        for path in referencedPaths.sorted() where representedPaths.insert(path).inserted {
            resources.append(FoundryPackageResource(
                logicalPath: path,
                packagePath: nil,
                location: FoundryPackageResourceResolver.isRemote(path) ? .remote : .unresolved,
                byteCount: nil,
                sha256: nil
            ))
        }
        resources.sort { $0.logicalPath < $1.logicalPath }

        try FoundryVTTDocumentIdentityValidator.validate(collections)
        let statistics = FoundryVTTStatisticsBuilder.build(collections)
        diagnostics.append(FoundryImportDiagnostic(
            severity: .information,
            code: "bridge-decoded",
            message: "Decoded MasterRPG Foundry bridge version 1 without evaluating scripts or HTML."
        ))
        return FoundryVTTImportPackage(
            sourceSHA256: source.sourceSHA256,
            kind: kind,
            manifestPath: nil,
            manifest: manifest,
            collections: collections,
            resources: resources,
            diagnostics: diagnostics,
            statistics: statistics
        )
    }

    func resourceData(logicalPaths: Set<String>, sourceUrl: URL) throws -> [String: Data] {
        let values = try sourceUrl.resourceValues(forKeys: [.fileSizeKey])
        guard let size = values.fileSize, size <= limits.maximumArchiveSize else {
            throw FoundryImportError.fileTooLarge(values.fileSize ?? Int.max)
        }
        try Task.checkCancellation()
        let data = try Data(contentsOf: sourceUrl, options: .mappedIfSafe)
        try Task.checkCancellation()
        let contents = try decodeContents(data, retainingAssetPaths: logicalPaths)
        guard Set(contents.assets.keys) == logicalPaths else {
            let missing = logicalPaths.subtracting(contents.assets.keys).sorted().first ?? "asset"
            throw FoundryImportError.resourceUnavailable(missing)
        }
        return contents.assets
    }

    func allResourceData(sourceUrl: URL) throws -> [String: Data] {
        let values = try sourceUrl.resourceValues(forKeys: [.fileSizeKey])
        guard let size = values.fileSize, size <= limits.maximumArchiveSize else {
            throw FoundryImportError.fileTooLarge(values.fileSize ?? Int.max)
        }
        try Task.checkCancellation()
        let data = try Data(contentsOf: sourceUrl, options: .mappedIfSafe)
        try Task.checkCancellation()
        return try decodeContents(data, retainingAssetPaths: nil).assets
    }
}

extension FoundryBridgeDecoder {
    fileprivate struct Contents {
        let header: [String: FoundryJSONValue]
        let documents: [FoundryBridgeDocumentRecord]
        let assetMetadata: [String: FoundryBridgeAssetMetadata]
        let assets: [String: Data]
        let assetReferences: [FoundryBridgeAssetReference]
        let diagnostics: [FoundryImportDiagnostic]
    }

    fileprivate func decodeContents(
        _ data: Data,
        retainingAssetPaths: Set<String>? = nil
    ) throws -> Contents {
        guard data.count <= limits.maximumArchiveSize else { throw FoundryImportError.fileTooLarge(data.count) }
        var header: [String: FoundryJSONValue]?
        var documents: [FoundryBridgeDocumentRecord] = []
        var assetMetadata: [String: FoundryBridgeAssetMetadata] = [:]
        var assets: [String: Data] = [:]
        var references: [FoundryBridgeAssetReference] = []
        var diagnostics: [FoundryImportDiagnostic] = []
        var omittedDiagnosticCount = 0
        let diagnosticLimit = max(0, limits.maximumDiagnosticCount)
        var endCounts: (documentCount: Int, assetCount: Int)?
        var decodedAssetBytes = 0
        let bridgeLineByteLimit = maximumBridgeLineByteCount()
        for (lineIndex, line) in FoundryVTTLineSequence(data).enumerated() {
            try Task.checkCancellation()
            guard lineIndex < max(0, limits.maximumRecordCount) else {
                throw FoundryImportError.tooManyDocuments(lineIndex + 1)
            }
            let trimmed = line.foundryTrimmingASCIIWhitespace()
            guard !trimmed.isEmpty else { continue }
            guard trimmed.count <= bridgeLineByteLimit else {
                throw FoundryImportError.fileTooLarge(trimmed.count)
            }
            let raw = try FoundryJSONDecoding.decode(Data(trimmed), context: "bridge line \(lineIndex + 1)")
            guard let object = raw.objectValue, let record = object["record"]?.stringValue else {
                throw FoundryImportError.invalidArchive("Bridge line \(lineIndex + 1) has no record kind.")
            }
            guard record == "asset" || trimmed.count <= limits.maximumEntrySize else {
                throw FoundryImportError.fileTooLarge(trimmed.count)
            }
            if header == nil, record != "manifest" {
                throw FoundryImportError.invalidManifest("The first bridge record is not the manifest.")
            }
            if endCounts != nil {
                throw FoundryImportError.invalidArchive("The bridge end record is not last.")
            }
            switch record {
            case "manifest":
                guard header == nil,
                      object["format"]?.stringValue == "masterrpg-foundry-bridge",
                      object["version"]?.integerValue == 1 else {
                    throw FoundryImportError.invalidManifest("The bridge format or version is unsupported.")
                }
                _ = try declaredCounts(
                    in: object,
                    context: "bridge manifest",
                    invalid: FoundryImportError.invalidManifest
                )
                header = object
            case "document":
                guard let collection = object["collection"]?.stringValue,
                      let uuid = object["uuid"]?.stringValue,
                      let documentData = object["data"], documentData.objectValue != nil else {
                    throw FoundryImportError.invalidArchive("Bridge document at line \(lineIndex + 1) is incomplete.")
                }
                documents.append(FoundryBridgeDocumentRecord(
                    collection: collection,
                    documentType: .inferred(from: object["documentType"]?.stringValue),
                    uuid: uuid,
                    parentUUID: object["parentUUID"]?.stringValue,
                    data: documentData
                ))
                guard documents.count <= limits.maximumDocumentCount else {
                    throw FoundryImportError.tooManyDocuments(documents.count)
                }
            case "asset":
                guard let rawPath = object["path"]?.stringValue,
                      let encoded = object["data"]?.stringValue,
                      let mediaType = object["mediaType"]?.stringValue,
                      mediaType.utf8.count <= 256,
                      object["encoding"]?.stringValue == "base64",
                      let expectedSHA = object["sha256"]?.stringValue else {
                    throw FoundryImportError.invalidArchive("Bridge asset at line \(lineIndex + 1) is incomplete.")
                }
                guard rawPath.utf8.count <= 4_096 else {
                    throw FoundryImportError.invalidArchive("A bridge asset path is too long.")
                }
                let path = try FoundryPackagePath.normalized(rawPath)
                guard assetMetadata[path] == nil else {
                    throw FoundryImportError.invalidArchive("The bridge contains duplicate asset path \(path).")
                }
                guard expectedSHA.count == 64,
                      expectedSHA.allSatisfy({ $0.isHexDigit && !$0.isUppercase }) else {
                    throw FoundryImportError.resourceIntegrityFailure(path)
                }
                guard decodedAssetBytes <= limits.maximumResourceBatchSize else {
                    throw FoundryImportError.fileTooLarge(decodedAssetBytes)
                }
                let remainingBatchBytes = limits.maximumResourceBatchSize - decodedAssetBytes
                let decoded = try FoundryBoundedBase64.decode(
                    encoded,
                    maximumDecodedByteCount: min(limits.maximumEntrySize, remainingBatchBytes),
                    invalidMessage: "Bridge asset at line \(lineIndex + 1) is not valid base64."
                )
                let (nextAssetBytes, overflow) = decodedAssetBytes.addingReportingOverflow(decoded.count)
                guard !overflow, nextAssetBytes <= limits.maximumResourceBatchSize else {
                    throw FoundryImportError.fileTooLarge(overflow ? Int.max : nextAssetBytes)
                }
                decodedAssetBytes = nextAssetBytes
                guard foundrySHA256(decoded) == expectedSHA else {
                    throw FoundryImportError.resourceIntegrityFailure(path)
                }
                assetMetadata[path] = FoundryBridgeAssetMetadata(
                    byteCount: decoded.count,
                    sha256: expectedSHA
                )
                guard assetMetadata.count <= limits.maximumDocumentCount else {
                    throw FoundryImportError.tooManyDocuments(assetMetadata.count)
                }
                if retainingAssetPaths == nil || retainingAssetPaths?.contains(path) == true {
                    assets[path] = decoded
                }
            case "assetReference":
                // A malformed reference is skipped with a diagnostic instead of ending the whole
                // import; the asset stays unresolved. See CODE_AUDIT_26 §5.61.
                guard let rawPath = object["path"]?.stringValue,
                      let status = object["status"]?.stringValue,
                      let path = try? normalizeReferencePath(rawPath, status: status) else {
                    if diagnostics.count < diagnosticLimit {
                        diagnostics.append(FoundryImportDiagnostic(
                            severity: .warning,
                            code: "invalid-bridge-asset-reference",
                            message: "Skipped the bridge asset reference at line \(lineIndex + 1): it is incomplete or its path is invalid."
                        ))
                    } else {
                        omittedDiagnosticCount += 1
                    }
                    continue
                }
                references.append(FoundryBridgeAssetReference(path: path, status: status))
                guard references.count <= limits.maximumDocumentCount else {
                    throw FoundryImportError.tooManyDocuments(references.count)
                }
            case "end":
                guard endCounts == nil else {
                    throw FoundryImportError.invalidArchive("The bridge contains two end records.")
                }
                endCounts = try declaredCounts(
                    in: object,
                    context: "bridge end record",
                    invalid: FoundryImportError.invalidArchive
                )
            default:
                if diagnostics.count < diagnosticLimit {
                    diagnostics.append(FoundryImportDiagnostic(
                        severity: .warning,
                        code: "unknown-bridge-record",
                        message: "Skipped unknown bridge record \(record) at line \(lineIndex + 1)."
                    ))
                } else {
                    omittedDiagnosticCount += 1
                }
            }
        }
        if omittedDiagnosticCount > 0, diagnosticLimit > 0 {
            if diagnostics.count == diagnosticLimit {
                diagnostics.removeLast()
                omittedDiagnosticCount += 1
            }
            diagnostics.append(FoundryImportDiagnostic(
                severity: .warning,
                code: "diagnostics-truncated",
                message: "Suppressed \(omittedDiagnosticCount) bridge diagnostics."
            ))
        }
        guard let header else { throw FoundryImportError.invalidManifest("The bridge manifest is missing.") }
        let manifestCounts = try declaredCounts(
            in: header,
            context: "bridge manifest",
            invalid: FoundryImportError.invalidManifest
        )
        guard let endCounts else {
            throw FoundryImportError.invalidArchive("The bridge end record is missing; the export may be truncated.")
        }
        guard manifestCounts.documentCount == endCounts.documentCount,
              manifestCounts.assetCount == endCounts.assetCount else {
            throw FoundryImportError.invalidArchive("The bridge manifest and end record counts do not match.")
        }
        guard manifestCounts.documentCount == documents.count else {
            throw FoundryImportError.invalidArchive(
                "The bridge declares \(manifestCounts.documentCount) documents but contains \(documents.count)."
            )
        }
        guard manifestCounts.assetCount == assetMetadata.count else {
            throw FoundryImportError.invalidArchive(
                "The bridge declares \(manifestCounts.assetCount) included assets but contains \(assetMetadata.count)."
            )
        }
        let duplicateReferences = Dictionary(grouping: references, by: \.path).filter { $0.value.count > 1 }
        guard duplicateReferences.isEmpty,
              Set(references.map(\.path)).isDisjoint(with: assetMetadata.keys) else {
            throw FoundryImportError.invalidArchive("The bridge contains duplicate normalized asset paths.")
        }
        return Contents(
            header: header,
            documents: documents,
            assetMetadata: assetMetadata,
            assets: assets,
            assetReferences: references,
            diagnostics: diagnostics
        )
    }

    func declaredCounts(
        in object: [String: FoundryJSONValue],
        context: String,
        invalid: (String) -> FoundryImportError
    ) throws -> (documentCount: Int, assetCount: Int) {
        guard let rawDocumentCount = object["documentCount"]?.integerValue,
              rawDocumentCount >= 0,
              let documentCount = Int(exactly: rawDocumentCount),
              let rawAssetCount = object["assetCount"]?.integerValue,
              rawAssetCount >= 0,
              let assetCount = Int(exactly: rawAssetCount) else {
            throw invalid("The \(context) must declare nonnegative integer documentCount and assetCount values.")
        }
        let maximumCount = max(documentCount, assetCount)
        guard maximumCount <= limits.maximumDocumentCount else {
            throw FoundryImportError.tooManyDocuments(maximumCount)
        }
        return (documentCount, assetCount)
    }

    /// Asset records carry Base64, so their encoded JSON line is necessarily larger than the
    /// decoded `maximumEntrySize`. Bound it to canonical Base64 expansion plus small metadata,
    /// and still apply the decoded limit before allocating bytes.
    func maximumBridgeLineByteCount() -> Int {
        let archiveLimit = max(0, limits.maximumArchiveSize)
        let decodedLimit = max(0, limits.maximumEntrySize)
        let (roundedDecodedLimit, roundingOverflow) = decodedLimit.addingReportingOverflow(2)
        guard !roundingOverflow else { return archiveLimit }
        let groups = roundedDecodedLimit / 3
        let (encodedLimit, encodingOverflow) = groups.multipliedReportingOverflow(by: 4)
        guard !encodingOverflow else { return archiveLimit }
        let (lineLimit, metadataOverflow) = encodedLimit.addingReportingOverflow(65_536)
        return min(archiveLimit, metadataOverflow ? Int.max : lineLimit)
    }

    func normalizeReferencePath(_ path: String, status: String) throws -> String {
        if status == "remote" {
            guard let components = URLComponents(string: path),
                  ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
                  components.host != nil else {
                throw FoundryImportError.invalidArchive("A remote bridge asset reference has an invalid URL.")
            }
            return path
        }
        return try FoundryPackagePath.normalized(path)
    }
}

// MARK: - Bridge Decode Models

private struct FoundryBridgeDocumentRecord {
    let collection: String
    let documentType: FoundryDocumentType
    let uuid: String
    let parentUUID: String?
    let data: FoundryJSONValue
}

private struct FoundryBridgeGroupKey: Hashable {
    let collection: String
    let documentType: FoundryDocumentType
}

private struct FoundryBridgeAssetReference {
    let path: String
    let status: String
}

private struct FoundryBridgeAssetMetadata {
    let byteCount: Int
    let sha256: String
}

private extension FoundryDocument {
    func withBridgeSource(uuid: String, parentUUID: String?) -> Self {
        Self(
            id: id,
            documentId: documentId,
            documentType: documentType,
            subtype: subtype,
            name: name,
            folderId: folderId,
            sort: sort,
            imagePath: imagePath,
            descriptionHTML: descriptionHTML,
            parentId: parentId,
            sourceUUID: uuid,
            sourceParentUUID: parentUUID,
            embeddedDocuments: embeddedDocuments,
            references: references,
            unknownFieldNames: unknownFieldNames,
            rawData: rawData
        )
    }
}
