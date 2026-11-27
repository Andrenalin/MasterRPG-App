// @copyright André Trettin

import Foundation

/// One stable MasterRPG destination for a Foundry document or embedded element.
public struct FoundryImportMappingReference: Codable, Equatable, Hashable, Sendable {
    public init(module: NetworkModules, itemId: UUID, entryId: UUID? = nil) {
        self.module = module
        self.itemId = itemId
        self.entryId = entryId
    }

    public let module: NetworkModules
    public let itemId: UUID
    public let entryId: UUID?

    /// The archived and sent keys keep their `ID` spelling; the properties follow the
    /// project's `Id` casing. See CODE_AUDIT_29 §4.3.
    private enum CodingKeys: String, CodingKey {
        case module
        case itemId
        case entryId = "entryID"
    }
}

/// The import ledger keeps Foundry UUID links resolvable after projection into module models.
public struct FoundryImportMapping: Codable, Equatable, Identifiable, Sendable {
    public var id: String { foundryIdentifier }

    public init(foundryIdentifier: String, references: [FoundryImportMappingReference]) {
        self.foundryIdentifier = foundryIdentifier
        self.references = references
    }

    public let foundryIdentifier: String
    public let references: [FoundryImportMappingReference]
}

/// Versioned, normalized source data retained for RuleRPG and future system-aware interpretation.
///
/// Projected MasterRPG models are intentionally not the source of truth for system-specific
/// calculations, effects, permissions, macros, or custom module fields. Those remain in the raw
/// document envelopes contained by `package`. Privacy-disabled fields and duplicate raw container
/// arrays are deliberately absent, so this is field-preserving source data rather than a byte copy.
public struct FoundryImportArchive: Codable, Equatable, Identifiable, Sendable {
    public static let currentFormatVersion = 3

    public init(
        id: UUID,
        sourceScopeId: UUID? = nil,
        sourceFormat: String? = nil,
        sourceSemanticKey: String? = nil,
        importedAt: Date = .now,
        sourceFileName: String,
        package: FoundryVTTImportPackage,
        mappings: [FoundryImportMapping],
        warnings: [String] = []
    ) {
        self.id = id
        self.sourceScopeId = sourceScopeId ?? id
        self.sourceFormat = sourceFormat
        self.sourceSemanticKey = sourceSemanticKey
        self.formatVersion = Self.currentFormatVersion
        self.importedAt = importedAt
        self.sourceFileName = sourceFileName
        self.package = package
        self.mappings = mappings
        self.warnings = warnings
    }

    public let id: UUID
    /// Stable external-source identity used to derive every projected item UUID.
    public let sourceScopeId: UUID?
    /// Registry matching metadata. Optional so v1/v2 archives remain readable.
    public let sourceFormat: String?
    public let sourceSemanticKey: String?
    public let formatVersion: Int
    public let importedAt: Date
    public let sourceFileName: String
    public let package: FoundryVTTImportPackage
    public let mappings: [FoundryImportMapping]
    public let warnings: [String]

    /// The archived and sent keys keep their `ID` spelling; the properties follow the
    /// project's `Id` casing. See CODE_AUDIT_29 §4.3.
    private enum CodingKeys: String, CodingKey {
        case id
        case sourceScopeId = "sourceScopeID"
        case sourceFormat
        case sourceSemanticKey
        case formatVersion
        case importedAt
        case sourceFileName
        case package
        case mappings
        case warnings
    }
}

public struct FoundryImportArchiveSummary: Codable, Equatable, Identifiable, Sendable {
    public init(archive: FoundryImportArchive) {
        id = archive.id
        importedAt = archive.importedAt
        sourceFileName = archive.sourceFileName
        packageTitle = archive.package.manifest?.title ?? archive.sourceFileName
        packageKind = archive.package.kind
        documentCount = archive.package.statistics.topLevelDocumentCount
            + archive.package.statistics.embeddedDocumentCount
        sourceSHA256 = archive.package.sourceSHA256
    }

    public let id: UUID
    public let importedAt: Date
    public let sourceFileName: String
    public let packageTitle: String
    public let packageKind: FoundryVTTPackageKind
    public let documentCount: Int
    public let sourceSHA256: String?
}

public enum FoundryImportArchiveStoreError: LocalizedError, Equatable, Sendable {
    case unsupportedFormatVersion(Int)
    case archiveTooLarge(Int)

    public var errorDescription: String? {
        switch self {
        case .unsupportedFormatVersion(let version):
            "Foundry archive format version \(version) is not supported."
        case .archiveTooLarge(let byteCount):
            "The RuleRPG source archive is too large to save safely (\(byteCount) bytes)."
        }
    }
}

/// Actor-isolated storage for the RuleRPG hand-off archive.
///
/// The default location follows the app's existing iCloud-document fallback policy. A caller can
/// inject a temporary directory for tests. Saving is atomic and only happens after an import commit.
public actor FoundryImportArchiveStore {
    private let directoryUrl: URL
    private let maximumEncodedByteCount: Int

    public init(directoryUrl: URL? = nil, maximumEncodedByteCount: Int = 512 * ByteUnit.mebibyte) {
        self.directoryUrl = directoryUrl ?? Self.defaultDirectoryUrl
        self.maximumEncodedByteCount = maximumEncodedByteCount
    }

    public func save(_ archive: FoundryImportArchive) async throws {
        let data = try JSONCoding.iso8601SortedKeysEncoder.encode(archive)
        guard data.count <= maximumEncodedByteCount else {
            throw FoundryImportArchiveStoreError.archiveTooLarge(data.count)
        }
        let destination = url(for: archive.id)
        try await FileManager.default.updateFile(coordinatingAccessTo: destination) { coordinatedUrl in
            try FileManager.default.createDirectory(
                at: coordinatedUrl.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: coordinatedUrl, options: .atomic)
        }
    }

    public func archive(id: UUID) async throws -> FoundryImportArchive? {
        let archiveUrl = url(for: id)
        let status = try await FileManager.default.fileExists(coordinatingAccessAt: archiveUrl)
        guard status.exists, !status.isDirectory else { return nil }
        // The size is checked before the file is read, as `mapArchives` does, so a file synced
        // from elsewhere that exceeds the cap is not loaded whole. See CODE_AUDIT_26 §7.40.
        if let fileSize = try? archiveUrl.resourceValues(forKeys: [.fileSizeKey]).fileSize,
           fileSize > maximumEncodedByteCount {
            throw FoundryImportArchiveStoreError.archiveTooLarge(fileSize)
        }
        let data = try await FileManager.default.contentsOfFile(coordinatingAccessAt: archiveUrl)
        guard data.count <= maximumEncodedByteCount else {
            throw FoundryImportArchiveStoreError.archiveTooLarge(data.count)
        }
        return try decode(data)
    }

    public func summaries() async throws -> [FoundryImportArchiveSummary] {
        try await mapArchives(FoundryImportArchiveSummary.init)
            .sorted { $0.importedAt > $1.importedAt }
    }

    /// Provides iCloud-synced source identity hints when the small registry index is missing,
    /// for example after reinstalling the app or importing on another device.
    public func sourceRegistryEntries() async throws -> [ExternalImportSourceEntry] {
        let entries = try await mapArchives { archive in
            let scopeId = archive.sourceScopeId ?? archive.id
            let intrinsicScopeId = archive.package.manifest?.rawData
                .value(at: "source.instanceID")?.stringValue
                .flatMap(UUID.init(uuidString:))
            let inferredFormat: String
            if archive.package.documents.contains(where: { $0.subtype == "UniversalVTT" }) {
                inferredFormat = "universal-vtt"
            } else {
                inferredFormat = "foundry-\(archive.package.kind.rawValue)"
            }
            let semanticKey = archive.sourceSemanticKey ?? archive.package.manifest.map {
                "\(archive.package.kind.rawValue):\($0.id)"
            }
            return ExternalImportSourceEntry(
                scopeId: scopeId,
                format: archive.sourceFormat ?? inferredFormat,
                semanticKey: semanticKey,
                fileResourceAlias: nil,
                volumeResourceAlias: nil,
                lastKnownPathAlias: archive.sourceFileName,
                lastContentHash: archive.package.sourceSHA256,
                createdAt: archive.importedAt,
                lastImportedAt: archive.importedAt,
                intrinsicScopeAlias: intrinsicScopeId == scopeId ? nil : intrinsicScopeId
            )
        }
        var newestByScope: [UUID: ExternalImportSourceEntry] = [:]
        for entry in entries {
            guard let existing = newestByScope[entry.scopeId] else {
                newestByScope[entry.scopeId] = entry
                continue
            }
            if entry.lastImportedAt > existing.lastImportedAt {
                newestByScope[entry.scopeId] = entry
            }
        }
        return newestByScope.values.sorted { lhs, rhs in
            if lhs.lastImportedAt != rhs.lastImportedAt {
                return lhs.lastImportedAt > rhs.lastImportedAt
            }
            return lhs.scopeId.uuidString < rhs.scopeId.uuidString
        }
    }
}

private extension FoundryImportArchiveStore {
    static var defaultDirectoryUrl: URL {
        return FileManager.preferredRootUrl
            .appending(path: CloudDocumentController.documentDirName)
            .appending(path: "foundry")
            .appending(path: "archives")
    }

    func url(for id: UUID) -> URL {
        directoryUrl.appending(path: id.uuidString.lowercased()).appendingPathExtension("json")
    }

    func decode(_ data: Data) throws -> FoundryImportArchive {
        // The depth guard: without it, a deeply-nested `FoundryJSONValue` (e.g. from corrupted
        // iCloud sync or a restored backup of this archive directory) triggers unbounded
        // native-stack recursion — a stack-overflow trap, not a catchable Swift error — on
        // essentially every import attempt, since this path re-reads the archive directory
        // each time. See CODE_AUDIT §6.2, CODE_AUDIT_19 §9.17.
        let decoder = FoundryJSONDecoding.makeDecoder(isSourceJSON: false)
        decoder.dateDecodingStrategy = .iso8601
        let archive = try decoder.decode(FoundryImportArchive.self, from: data)
        guard (1...FoundryImportArchive.currentFormatVersion).contains(archive.formatVersion) else {
            throw FoundryImportArchiveStoreError.unsupportedFormatVersion(archive.formatVersion)
        }
        return archive
    }


    /// Decodes the stored archives one at a time and keeps only what `transform` extracts, so
    /// the memory peak is the largest single archive instead of the sum of all of them (each
    /// can be hundreds of megabytes of `FoundryJSONValue` tree). See CODE_AUDIT_15 §7.3.
    func mapArchives<T>(_ transform: (FoundryImportArchive) -> T) async throws -> [T] {
        let urls: [URL]
        do {
            urls = try FileManager.default.contentsOfDirectory(
                at: directoryUrl,
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            )
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            return []
        }
        var results: [T] = []
        for url in urls where url.pathExtension == "json" {
            try Task.checkCancellation()
            do {
                let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                guard values.isRegularFile == true else { continue }
                if let fileSize = values.fileSize, fileSize > maximumEncodedByteCount {
                    continue
                }
                let data = try await FileManager.default.contentsOfFile(coordinatingAccessAt: url)
                guard data.count <= maximumEncodedByteCount else { continue }
                results.append(transform(try decode(data)))
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // One interrupted, corrupt, or newer archive must not discard valid synced source
                // identity hints from every other archive in the directory.
                continue
            }
        }
        return results
    }
}
