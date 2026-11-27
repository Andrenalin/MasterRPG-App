// @copyright André Trettin

import CryptoKit
import Foundation

// MARK: - Public API

/// Reads a Foundry VTT game-system package into a stable interchange model for supported rules.
///
/// The result is deliberately independent of Core Data and the app's current RPG modules. A
/// `RuleRPG` can map or persist it without learning ZIP or LevelDB internals.
public struct FoundrySystemPackageReader: Sendable {
    public let limits: FoundryImportLimits

    public init(limits: FoundryImportLimits = .default) {
        self.limits = limits
    }

    public func read(from url: URL) async throws -> FoundryRulePackage {
        let limits = limits
        // Structured and scope-balanced; cancellation propagates. See CODE_AUDIT_18 §4.4.
        return try await url.withSecurityScopedAccess { url in
            let source = try FoundryVTTDataSource(url: url, limits: limits)
            return try Self.readSynchronously(source: source, limits: limits)
        }
    }

    /// Reuses a ZIP central directory the caller already parsed (`FoundryVTTImportReader.read(from:)`
    /// parses the same archive for its own document decode) instead of re-reading and re-parsing the
    /// same file from disk a second time. `FoundryZIPArchive` holds the full archive bytes already in
    /// memory, so no file access — and no security-scoped resource — is needed here. See CODE_AUDIT_9 §7.3.
    func read(reusingArchive archive: FoundryZIPArchive, sourceSHA256: String) async throws -> FoundryRulePackage {
        let limits = limits
        // Structured; cancellation propagates. See CODE_AUDIT_18 §4.4.
        return try await runOffCallerExecutor {
            let source = FoundryVTTDataSource.archive(archive, sourceSHA256: sourceSHA256)
            return try Self.readSynchronously(source: source, limits: limits)
        }
    }

    /// Reopens resources issued by `read(from:)` while reusing the importer's path, CRC, size,
    /// provenance, and per-resource integrity checks.
    public func readResources(
        _ resources: [FoundryPackageResource],
        from url: URL,
        in package: FoundryRulePackage
    ) async throws -> [FoundryPackageResourceData] {
        guard Set(resources).count == resources.count else {
            throw FoundryImportError.duplicateResourceRequest
        }
        let limits = limits
        // Structured and scope-balanced; cancellation propagates. See CODE_AUDIT_18 §4.4.
        return try await url.withSecurityScopedAccess { url in
            let source = try FoundryVTTDataSource(url: url, limits: limits)
            if let expectedSourceSHA256 = package.sourceSHA256,
               source.sourceSHA256 != expectedSourceSHA256 {
                throw FoundryImportError.sourceMismatch
            }
            let manifestPath = try source.manifestPath()
            guard manifestPath == package.manifestPath,
                  let manifestData = try source.data(forPath: manifestPath),
                  try FoundryManifestDecoder().decode(manifestData) == package.manifest else {
                throw FoundryImportError.sourceMismatch
            }

            let issuedResources = Set(package.resources)
            var result: [FoundryPackageResourceData] = []
            result.reserveCapacity(resources.count)
            var totalResourceBytes = 0
            for resource in resources {
                try Task.checkCancellation()
                guard issuedResources.contains(resource),
                      resource.location == .packaged,
                      let packagePath = resource.packagePath,
                      let byteCount = resource.byteCount,
                      let sha256 = resource.sha256,
                      let data = try source.data(forPath: packagePath) else {
                    throw FoundryImportError.resourceUnavailable(resource.logicalPath)
                }
                guard data.count == byteCount,
                      foundrySHA256(data) == sha256 else {
                    throw FoundryImportError.resourceIntegrityFailure(resource.logicalPath)
                }
                let (nextResourceBytes, overflow) = totalResourceBytes.addingReportingOverflow(data.count)
                guard !overflow, nextResourceBytes <= limits.maximumResourceBatchSize else {
                    throw FoundryImportError.fileTooLarge(overflow ? Int.max : nextResourceBytes)
                }
                totalResourceBytes = nextResourceBytes
                result.append(FoundryPackageResourceData(resource: resource, data: data))
            }
            return result
        }
    }

    public func readResource(
        _ resource: FoundryPackageResource,
        from url: URL,
        in package: FoundryRulePackage
    ) async throws -> Data {
        guard let data = try await readResources([resource], from: url, in: package).first?.data else {
            throw FoundryImportError.resourceUnavailable(resource.logicalPath)
        }
        return data
    }
}

// MARK: - Package Assembly Orchestration

private extension FoundrySystemPackageReader {
    static func readSynchronously(source: FoundryVTTDataSource, limits: FoundryImportLimits) throws -> FoundryRulePackage {
        let manifestPath = try source.manifestPath()
        guard let manifestData = try source.data(forPath: manifestPath) else {
            throw FoundryImportError.missingManifest
        }
        let manifest = try FoundryManifestDecoder().decode(manifestData)
        let basePath = String(manifestPath.dropLast("system.json".count))
        
        let proposedTemplatePath = try FoundryPackagePath.join(basePath, "template.json")
        let templatePath = source.contains(path: proposedTemplatePath) ? proposedTemplatePath : nil
        let templateData = try templatePath.flatMap { try source.data(forPath: $0) }
        let decodedTemplate = try templateData.map { try FoundryJSONDecoding.decode($0, context: "template.json") }
        let schemas = try decodedTemplate.map(FoundryTemplateDecoder().decode) ?? []
        
        var diagnostics: [FoundryImportDiagnostic] = []
        var compendiums: [FoundryCompendium] = []
        var totalEncodedTableBytes = 0
        var totalDecodedRecordBytes = 0
        var totalLevelDBRecords = 0
        var totalDocuments = 0
        
        for pack in manifest.packs {
            try Task.checkCancellation()
            let packPath = try FoundryPackagePath.join(basePath, pack.path)
            let packPrefix = packPath.hasSuffix("/") ? packPath : packPath + "/"
            let packPaths = source.paths(withPrefix: packPrefix)
            let tablePaths = packPaths
                .filter { $0.hasPrefix(packPrefix) && $0.lowercased().hasSuffix(".ldb") }
                .sorted()
            guard !tablePaths.isEmpty else {
                throw FoundryImportError.missingPack(pack.name)
            }
            guard tablePaths.count == 1 else {
                throw FoundryImportError.unsupportedLevelDBTableSet(pack: pack.name, tableCount: tablePaths.count)
            }
            
            let logPaths = packPaths
                .filter { path in
                    guard path.hasPrefix(packPrefix), path.lowercased().hasSuffix(".log") else { return false }
                    return URL(filePath: path).deletingPathExtension().lastPathComponent.allSatisfy(\.isNumber)
                }
                .sorted()
            for logPath in logPaths {
                guard let logData = try source.data(forPath: logPath) else { continue }
                guard logData.isEmpty else {
                    throw FoundryImportError.unsupportedLevelDBLog(logPath)
                }
            }
            
            var records: [FoundryLevelDBRecord] = []
            for tablePath in tablePaths {
                guard let data = try source.data(forPath: tablePath) else { continue }
                let (nextSize, overflow) = totalEncodedTableBytes.addingReportingOverflow(data.count)
                guard !overflow, nextSize <= limits.maximumRuleDataSize else {
                    throw FoundryImportError.fileTooLarge(overflow ? Int.max : nextSize)
                }
                totalEncodedTableBytes = nextSize
                
                let tableRecords = try FoundryLevelDBTableReader(limits: limits).records(in: data)
                let (nextRecordCount, recordCountOverflow) = totalLevelDBRecords.addingReportingOverflow(tableRecords.count)
                guard !recordCountOverflow, nextRecordCount <= limits.maximumDocumentCount else {
                    throw FoundryImportError.tooManyDocuments(recordCountOverflow ? Int.max : nextRecordCount)
                }
                totalLevelDBRecords = nextRecordCount
                for record in tableRecords {
                    let recordSize = record.key.utf8.count + record.value.count + MemoryLayout<UInt64>.size + 1
                    let (nextDecodedSize, decodedOverflow) = totalDecodedRecordBytes.addingReportingOverflow(recordSize)
                    guard !decodedOverflow, nextDecodedSize <= limits.maximumRuleDataSize else {
                        throw FoundryImportError.fileTooLarge(decodedOverflow ? Int.max : nextDecodedSize)
                    }
                    totalDecodedRecordBytes = nextDecodedSize
                }
                records.append(contentsOf: tableRecords)
            }
            
            let result = try FoundryCompendiumDecoder(
                systemId: manifest.id,
                pack: pack,
                maximumDocumentCount: limits.maximumDocumentCount
            ).decode(records)
            compendiums.append(result.compendium)
            diagnostics.append(contentsOf: result.diagnostics)
            totalDocuments += result.compendium.rules.count
            guard totalDocuments <= limits.maximumDocumentCount else {
                throw FoundryImportError.tooManyDocuments(totalDocuments)
            }
        }
        
        if manifest.id != "ds4" {
            diagnostics.append(FoundryImportDiagnostic(
                severity: .information,
                code: "generic-system-interpretation",
                message: "Supported Actor and Item payloads are preserved, but only generic subtype categories are available for system \(manifest.id)."
            ))
        }
        
        let contentVersions = Set(compendiums.flatMap(\.rules).compactMap {
            $0.rawData.value(at: "_stats.systemVersion")?.stringValue
        })
        for contentVersion in contentVersions.sorted() where contentVersion != manifest.version {
            diagnostics.append(FoundryImportDiagnostic(
                severity: .information,
                code: "content-system-version",
                message: "Compendium records were authored with system version \(contentVersion); the package manifest is \(manifest.version)."
            ))
        }
        
        diagnostics.append(FoundryImportDiagnostic(
            severity: .information,
            code: "rules-decoded",
            message: "Decoded \(totalDocuments) top-level rules from \(compendiums.count) compendiums."
        ))
        
        let assetPaths = FoundryAssetPathCollector.paths(in: foundrySystemPackageRawValues(in: compendiums)).sorted()
        let resources = try FoundryPackageResourceResolver.resolve(
            assetPaths: assetPaths,
            packageDirectory: "systems",
            packageId: manifest.id,
            basePath: basePath,
            contains: { source.contains(path: $0) },
            data: { try source.data(forPath: $0) },
            limits: limits
        )
        let licensePaths = source.paths
            .filter { !$0.hasSuffix("/") && FoundryPackagePath.isLicensePath($0) }
            .sorted()
        var totalTextResourceBytes = 0
        var licenseDocuments: [FoundryPackageTextResource] = []
        for path in licensePaths {
            try Task.checkCancellation()
            guard let data = try source.data(forPath: path) else { continue }
            try consumeTextResourceBytes(
                data.count,
                total: &totalTextResourceBytes,
                maximum: limits.maximumRuleDataSize
            )
            guard let content = String(data: data, encoding: .utf8) else { continue }
            licenseDocuments.append(FoundryPackageTextResource(path: path, content: content))
        }
        let localizations = try FoundryLocalizationDecoder().decode(
            manifest: manifest,
            basePath: basePath,
            source: source,
            totalTextResourceBytes: &totalTextResourceBytes,
            maximumTextResourceBytes: limits.maximumRuleDataSize
        )
        return FoundryRulePackage(
            sourceSHA256: source.sourceSHA256,
            manifest: manifest,
            manifestPath: manifestPath,
            templatePath: templatePath,
            templateData: decodedTemplate,
            schemas: schemas,
            compendiums: compendiums,
            localizations: localizations,
            assetPaths: assetPaths,
            resources: resources,
            licensePaths: licensePaths,
            licenseDocuments: licenseDocuments,
            diagnostics: diagnostics
        )
    }
}

internal extension FoundrySystemPackageReader {
    // Internal, not private: the split-out decoders use it. See CODE_AUDIT_29 §9.9.
    static func consumeTextResourceBytes(
        _ byteCount: Int,
        total: inout Int,
        maximum: Int
    ) throws {
        let (nextTotal, overflow) = total.addingReportingOverflow(byteCount)
        guard !overflow, nextTotal <= maximum else {
            throw FoundryImportError.fileTooLarge(overflow ? Int.max : nextTotal)
        }
        total = nextTotal
    }
}

// MARK: - Package Data Source

// The archive/directory source is shared with the world/module import reader
// (`FoundryVTTDataSource`): both used to carry their own copy of the symlink-safe directory walker
// and path-containment checks, so a hardening fix in one left the other exposed.
// See CODE_AUDIT_15 §9.10.
extension FoundryVTTDataSource {
    func manifestPath() throws -> String {
        let candidates = paths.filter { path in
            path.split(separator: "/").last?.lowercased() == "system.json"
        }
        if candidates.contains("system.json") {
            return "system.json"
        }
        guard !candidates.isEmpty else { throw FoundryImportError.missingManifest }
        guard candidates.count == 1 else { throw FoundryImportError.ambiguousManifest }
        return candidates[0]
    }
}

// MARK: - Localization Decoding

// `FoundryPackagePath` (path utilities) now lives in the shared `FoundryPackageResolution.swift`,
// used by both this reader and `FoundryVTTImportReader`. See CODE_AUDIT §9.2, §9.5.

// MARK: - Manifest Decoding

// `FoundryJSONDecoder` now lives in the shared `FoundryPackageResolution.swift` as
// `FoundryJSONDecoding`, used by both this reader and `FoundryVTTImportReader`. See
// CODE_AUDIT §9.3.

// MARK: - Template Decoding

// `FoundryCompendiumDecoder` and `FoundryCanonicalKey` now live in
// `FoundrySystemCompendiumDecoding.swift`. See CODE_AUDIT §9.8.

// MARK: - Reference Decoding

// `FoundryAssetCollector` and `FoundryPackageResourceResolver` now live in the shared
// `FoundryPackageResolution.swift` (as `FoundryAssetPathCollector` and
// `FoundryPackageResourceResolver`), used by both this reader and `FoundryVTTImportReader`.
// See CODE_AUDIT §9.1, §9.4, §6.1.

/// Gathers every raw JSON value under a system package's compendiums (rules, their effects,
/// and embedded rules with their own effects) for `FoundryAssetPathCollector` to walk —
/// specific to this reader's `FoundryCompendium`/`FoundryRuleDefinition` document model, unlike
/// the shared collector itself.
private func foundrySystemPackageRawValues(in compendiums: [FoundryCompendium]) -> [FoundryJSONValue] {
    var values: [FoundryJSONValue] = []
    for rule in compendiums.flatMap(\.rules) {
        values.append(rule.rawData)
        values.append(contentsOf: rule.effects.map(\.rawData))
        for embedded in rule.embeddedRules {
            values.append(embedded.rawData)
            values.append(contentsOf: embedded.effects.map(\.rawData))
        }
    }
    return values
}

// MARK: - Shared Utilities

func flatten(_ value: FoundryJSONValue, path: [String]) -> [FoundryRuleValue] {
    switch value {
    case .object(let object) where !object.isEmpty:
        return object.keys.sorted().flatMap { key in
            flatten(object[key] ?? .null, path: path + [key])
        }
    default:
        return [FoundryRuleValue(path: path.joined(separator: "."), value: value)]
    }
}

func foundrySHA256(_ data: Data) -> String {
    SHA256.hash(data: data)
        .map { String($0, radix: 16).leftPadded(to: 2, with: "0") }
        .joined()
}

extension FoundryJSONValue {
    var scalarString: String? {
        switch self {
        case .string(let value): value
        case .integer(let value): String(value)
        case .unsignedInteger(let value): String(value)
        case .number(let value): String(value)
        default: nil
        }
    }

    var valueKind: FoundryRuleField.ValueKind {
        switch self {
        case .object: .object
        case .array: .array
        case .string: .string
        case .integer: .integer
        case .unsignedInteger: .unsignedInteger
        case .number: .number
        case .bool: .boolean
        case .null: .null
        }
    }
}

extension FoundryRuleCategory {
    static func category(systemId: String, documentType: String, subtype: String) -> Self {
        guard systemId == "ds4" else { return Self(rawValue: subtype) }
        return switch subtype {
        case "character": .character
        case "creature": .creature
        case "spell": .spell
        case "talent": .talent
        case "weapon": .weapon
        case "armor": .armor
        case "shield": .shield
        case "equipment": .equipment
        case "loot": .loot
        case "racialAbility": .ancestryAbility
        case "language": .language
        case "alphabet": .script
        case "specialCreatureAbility": .creatureAbility
        default: Self(rawValue: subtype.isEmpty ? documentType.lowercased() : subtype)
        }
    }
}

extension String {
    func suffix(after prefix: String) -> String? {
        guard hasPrefix(prefix) else { return nil }
        return String(dropFirst(prefix.count))
    }

    func foundryIDComponents(expectedCount: Int) -> [String]? {
        let components = split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard components.count == expectedCount, components.allSatisfy({ !$0.isEmpty }) else { return nil }
        return components
    }

    func leftPadded(to length: Int, with character: Character) -> String {
        guard count < length else { return self }
        return String(repeating: String(character), count: length - count) + self
    }

}
