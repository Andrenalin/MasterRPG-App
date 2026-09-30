// @copyright André Trettin

import Foundation

/// Actor-isolated registry which separates source identity from mutable file bytes.
///
/// A stable scope follows a renamed file through its resource identifier, survives an atomic file
/// replacement through its path alias, and avoids silently merging copied worlds or arbitrary VTTs.
/// First-time scopes are deterministic from intrinsic, semantic, or content identity so separate
/// devices converge before their indexes synchronize; an explicit copied-source choice remains new.
public actor ExternalImportSourceRegistry {
    public static let shared = ExternalImportSourceRegistry()

    public init(directoryURL: URL? = nil) {
        self.explicitDirectoryURL = directoryURL
    }

    public func resolve(
        _ descriptor: ExternalImportSourceDescriptor,
        fallbackEntries: [ExternalImportSourceEntry] = []
    ) async throws -> ExternalImportSourceResolution {
        let storedEntries = try await load()
        let entries = Self.merging(storedEntries, with: fallbackEntries)
        let aliases = Self.aliases(for: descriptor.sourceURL)
        return Self.resolve(descriptor, among: entries, aliases: aliases)
    }

    /// Atomically revalidates the reviewed identity and reserves it before domain mutation starts.
    ///
    /// Unlike `resolve`, this method mutates the registry. Call it only from the serialized commit
    /// path. A failed domain transaction can safely leave the reservation behind: its purpose is to
    /// ensure all later reviews derive IDs from the same canonical source scope.
    public func claim(
        _ intent: ExternalImportSourceClaimIntent,
        descriptor: ExternalImportSourceDescriptor,
        fallbackEntries: [ExternalImportSourceEntry] = [],
        claimedAt: Date = .now
    ) async throws -> ExternalImportSourceClaimResult {
        let aliases = Self.aliases(for: descriptor.sourceURL)
        let newCopyScopeID: UUID = switch intent {
        case .selectedNew(let scopeID): scopeID
        case .resolved, .selectedExisting: UUID()
        }
        let destination = indexURL
        return try await FileManager.default.updateFile(coordinatingAccessTo: destination) { coordinatedURL in
            let storedEntries = try Self.decodeEntriesIfPresent(at: coordinatedURL)
            let resolutionEntries = Self.merging(storedEntries, with: fallbackEntries)
            let latestResolution = Self.resolve(
                descriptor,
                among: resolutionEntries,
                aliases: aliases,
                newCopyScopeID: newCopyScopeID
            )

            let result = Self.revalidate(
                intent,
                latestResolution: latestResolution,
                descriptor: descriptor,
                entries: resolutionEntries,
                aliases: aliases
            )
            guard case .claimed(let scopeID) = result else { return result }

            let updatedEntries = Self.registering(
                scopeID: scopeID,
                descriptor: descriptor,
                aliases: aliases,
                importedAt: claimedAt,
                in: storedEntries
            )
            try Self.write(updatedEntries, to: coordinatedURL)
            return result
        }
    }

    /// Registers a newly chosen scope or refreshes the aliases of an existing one.
    public func register(
        scopeID: UUID,
        descriptor: ExternalImportSourceDescriptor,
        importedAt: Date = .now
    ) async throws {
        let aliases = Self.aliases(for: descriptor.sourceURL)
        let destination = indexURL
        try await FileManager.default.updateFile(coordinatingAccessTo: destination) { coordinatedURL in
            let entries = try Self.decodeEntriesIfPresent(at: coordinatedURL)
            let updatedEntries = Self.registering(
                scopeID: scopeID,
                descriptor: descriptor,
                aliases: aliases,
                importedAt: importedAt,
                in: entries
            )
            try Self.write(updatedEntries, to: coordinatedURL)
        }
    }

    public func allEntries() async throws -> [ExternalImportSourceEntry] {
        try await load()
    }

    private static let currentFormatVersion = 2
    private let explicitDirectoryURL: URL?

    /// Resolved on every use (not captured at init), so the shared registry follows the iCloud
    /// root after an identity change. See CODE_AUDIT_19 §3.8.
    private var directoryURL: URL {
        explicitDirectoryURL ?? FileManager.preferredRootUrl
            .appending(path: CloudDocumentController.documentDirName)
            .appending(path: "foundry")
            .appending(path: "sources", directoryHint: .isDirectory)
    }
}

// Internal, not private: the source matching lives in ExternalImportSourceRegistry+Matching.swift.
extension ExternalImportSourceRegistry {
    struct Index: Codable, Sendable {
        let formatVersion: Int
        let entries: [ExternalImportSourceEntry]
    }

    struct SourceAliases: Sendable {
        let file: String?
        let volume: String?
        let path: String
    }

    var indexURL: URL {
        directoryURL.appending(path: "sources.json")
    }

    func load() async throws -> [ExternalImportSourceEntry] {
        let status = try await FileManager.default.fileExists(coordinatingAccessAt: indexURL)
        guard status.exists, !status.isDirectory else { return [] }
        let data = try await FileManager.default.contentsOfFile(coordinatingAccessAt: indexURL)
        return try Self.decodeEntries(from: data)
    }

    static func decodeEntriesIfPresent(at url: URL) throws -> [ExternalImportSourceEntry] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try decodeEntries(from: Data(contentsOf: url))
    }

    static func decodeEntries(from data: Data) throws -> [ExternalImportSourceEntry] {
        let index = try JSONCoding.iso8601Decoder.decode(Index.self, from: data)
        guard (1...Self.currentFormatVersion).contains(index.formatVersion) else {
            throw ExternalImportSourceRegistryError.unsupportedIndexVersion(index.formatVersion)
        }
        return index.entries
    }

    static func encodedIndex(_ entries: [ExternalImportSourceEntry]) throws -> Data {
        try JSONCoding.iso8601SortedKeysEncoder.encode(Index(formatVersion: Self.currentFormatVersion, entries: entries))
    }

    static func merging(
        _ storedEntries: [ExternalImportSourceEntry],
        with fallbackEntries: [ExternalImportSourceEntry]
    ) -> [ExternalImportSourceEntry] {
        var byScope: [UUID: ExternalImportSourceEntry] = [:]
        for entry in fallbackEntries {
            guard let existing = byScope[entry.scopeID] else {
                byScope[entry.scopeID] = entry
                continue
            }
            if entry.lastImportedAt > existing.lastImportedAt {
                byScope[entry.scopeID] = entry
            }
        }

        // The local registry retains physical aliases which an archive intentionally omits. Prefer
        // its newest entry for a scope even when a synced archive has a later import timestamp.
        var storedByScope: [UUID: ExternalImportSourceEntry] = [:]
        for entry in storedEntries {
            guard let existing = storedByScope[entry.scopeID] else {
                storedByScope[entry.scopeID] = entry
                continue
            }
            if entry.lastImportedAt > existing.lastImportedAt {
                storedByScope[entry.scopeID] = entry
            }
        }
        for (scopeID, entry) in storedByScope {
            byScope[scopeID] = entry
        }
        return Array(byScope.values)
    }
}
