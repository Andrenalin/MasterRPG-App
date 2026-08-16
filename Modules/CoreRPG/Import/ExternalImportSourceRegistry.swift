// @copyright André Trettin

import Foundation

/// Controls whether a semantic package identifier can select an existing source without asking.
public enum ExternalImportSemanticMatchPolicy: String, Codable, Equatable, Sendable {
    /// Appropriate for globally named packages such as Foundry systems and modules.
    case automatic
    /// Appropriate for worlds and arbitrary files which may have been copied or duplicated.
    case requiresConfirmation
}

/// Read-only facts used to resolve a stable source scope before domain IDs are derived.
public struct ExternalImportSourceDescriptor: Sendable {
    public init(
        format: String,
        semanticKey: String? = nil,
        intrinsicScopeID: UUID? = nil,
        sourceURL: URL,
        contentHash: String? = nil,
        semanticMatchPolicy: ExternalImportSemanticMatchPolicy = .requiresConfirmation
    ) {
        self.format = format
        self.semanticKey = semanticKey
        self.intrinsicScopeID = intrinsicScopeID
        self.sourceURL = sourceURL
        self.contentHash = contentHash
        self.semanticMatchPolicy = semanticMatchPolicy
    }

    public let format: String
    public let semanticKey: String?
    public let intrinsicScopeID: UUID?
    public let sourceURL: URL
    public let contentHash: String?
    public let semanticMatchPolicy: ExternalImportSemanticMatchPolicy
}

/// Small source index entry. Bookmarks and source contents are deliberately not stored.
public struct ExternalImportSourceEntry: Codable, Equatable, Identifiable, Sendable {
    public init(
        scopeID: UUID,
        format: String,
        semanticKey: String?,
        fileResourceAlias: String?,
        volumeResourceAlias: String?,
        lastKnownPathAlias: String,
        lastContentHash: String?,
        createdAt: Date,
        lastImportedAt: Date,
        intrinsicScopeAlias: UUID? = nil
    ) {
        self.scopeID = scopeID
        self.format = format
        self.semanticKey = semanticKey
        self.fileResourceAlias = fileResourceAlias
        self.volumeResourceAlias = volumeResourceAlias
        self.lastKnownPathAlias = lastKnownPathAlias
        self.lastContentHash = lastContentHash
        self.createdAt = createdAt
        self.lastImportedAt = lastImportedAt
        self.intrinsicScopeAlias = intrinsicScopeAlias
    }

    public var id: UUID { scopeID }

    public let scopeID: UUID
    public let format: String
    public let semanticKey: String?
    public let fileResourceAlias: String?
    public let volumeResourceAlias: String?
    public let lastKnownPathAlias: String
    public let lastContentHash: String?
    public let createdAt: Date
    public let lastImportedAt: Date
    /// Records a deliberate reassignment of a Foundry bridge instance identity to another scope.
    ///
    /// Older index entries omit this optional field. An entry whose `scopeID` is the bridge's
    /// intrinsic ID remains a backwards-compatible implicit candidate alongside explicit aliases.
    public let intrinsicScopeAlias: UUID?
}

public enum ExternalImportSourceResolution: Equatable, Sendable {
    /// The source is new or has an unambiguous intrinsic, file-resource, path, or semantic match.
    case resolved(scopeID: UUID)
    /// A copied/moved semantic source could update an existing import or become a new source.
    case requiresSelection(existing: [ExternalImportSourceEntry], proposedScopeID: UUID)
}

/// The identity choice that was reviewed before a commit began.
public enum ExternalImportSourceClaimIntent: Equatable, Sendable {
    /// Preflight found no ambiguity. The registry must revalidate this proposal at commit time.
    case resolved(scopeID: UUID)
    /// The user explicitly chose one of the existing source scopes offered by preflight.
    case selectedExisting(scopeID: UUID)
    /// The user explicitly chose to keep a copied source separate.
    case selectedNew(scopeID: UUID)

    public var scopeID: UUID {
        switch self {
        case .resolved(let scopeID), .selectedExisting(let scopeID), .selectedNew(let scopeID):
            scopeID
        }
    }
}

/// Result of atomically revalidating and reserving a source scope immediately before a commit.
public enum ExternalImportSourceClaimResult: Equatable, Sendable {
    case claimed(scopeID: UUID)
    /// Another commit claimed the same unambiguous source after this review was prepared.
    case requiresRemapping(canonicalScopeID: UUID)
    /// Source identity became ambiguous after review and needs a fresh explicit choice.
    case requiresSelection(existing: [ExternalImportSourceEntry], proposedScopeID: UUID)
}

public enum ExternalImportSourceRegistryError: LocalizedError, Equatable, Sendable {
    case unsupportedIndexVersion(Int)

    public var errorDescription: String? {
        switch self {
        case .unsupportedIndexVersion(let version):
            "External import source index version \(version) is not supported."
        }
    }
}

/// Actor-isolated registry which separates source identity from mutable file bytes.
///
/// A stable scope follows a renamed file through its resource identifier, survives an atomic file
/// replacement through its path alias, and avoids silently merging copied worlds or arbitrary VTTs.
/// First-time scopes are deterministic from intrinsic, semantic, or content identity so separate
/// devices converge before their indexes synchronize; an explicit copied-source choice remains new.
public actor ExternalImportSourceRegistry {
    public static let shared = ExternalImportSourceRegistry()

    public init(directoryURL: URL? = nil) {
        self.directoryURL = directoryURL ?? FileManager.preferredRootUrl
            .appending(path: CloudDocumentController.documentDirName)
            .appending(path: "foundry")
            .appending(path: "sources", directoryHint: .isDirectory)
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
    private let directoryURL: URL
}

private extension ExternalImportSourceRegistry {
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
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let index = try decoder.decode(Index.self, from: data)
        guard (1...Self.currentFormatVersion).contains(index.formatVersion) else {
            throw ExternalImportSourceRegistryError.unsupportedIndexVersion(index.formatVersion)
        }
        return index.entries
    }

    static func encodedIndex(_ entries: [ExternalImportSourceEntry]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(Index(formatVersion: Self.currentFormatVersion, entries: entries))
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

    static func resolve(
        _ descriptor: ExternalImportSourceDescriptor,
        among entries: [ExternalImportSourceEntry],
        aliases: SourceAliases,
        newCopyScopeID: UUID = UUID()
    ) -> ExternalImportSourceResolution {
        let compatible = entries.filter { isCompatible($0, with: descriptor) }

        if let intrinsicScopeID = descriptor.intrinsicScopeID {
            // A copied Foundry world can retain the bridge instance ID. Explicit aliases make each
            // user-created scope a durable candidate; physical aliases decide between candidates.
            let reassignedMatches = compatible.filter { $0.intrinsicScopeAlias == intrinsicScopeID }
            let implicitMatches = compatible.filter { $0.scopeID == intrinsicScopeID }
            let intrinsicMatches = mergingByScope(implicitMatches, reassignedMatches)
            guard !intrinsicMatches.isEmpty else { return .resolved(scopeID: intrinsicScopeID) }

            let exactFiles = exactFileMatches(in: intrinsicMatches, aliases: aliases)
            if let resolution = resolution(
                forExactMatches: exactFiles,
                proposedScopeID: newCopyScopeID
            ) {
                return resolution
            }

            let pathMatches = intrinsicMatches.filter { $0.lastKnownPathAlias == aliases.path }
            if let resolution = resolution(
                forExactMatches: pathMatches,
                proposedScopeID: newCopyScopeID
            ) {
                return resolution
            }

            if intrinsicMatches.count == 1,
               descriptor.semanticMatchPolicy == .automatic,
               let match = intrinsicMatches.first {
                return .resolved(scopeID: match.scopeID)
            }
            return .requiresSelection(
                existing: sorted(intrinsicMatches),
                proposedScopeID: newCopyScopeID
            )
        }

        let fileMatches = exactFileMatches(in: compatible, aliases: aliases)
        if let resolution = resolution(forExactMatches: fileMatches, proposedScopeID: newCopyScopeID) {
            return resolution
        }

        let pathMatches = compatible.filter { $0.lastKnownPathAlias == aliases.path }
        if !pathMatches.isEmpty {
            if descriptor.semanticMatchPolicy == .automatic,
               let resolution = resolution(forExactMatches: pathMatches, proposedScopeID: newCopyScopeID) {
                return resolution
            }
            return .requiresSelection(existing: sorted(pathMatches), proposedScopeID: newCopyScopeID)
        }

        let semanticMatches: [ExternalImportSourceEntry]
        if let semanticKey = descriptor.semanticKey {
            semanticMatches = compatible.filter { $0.semanticKey == semanticKey }
        } else {
            semanticMatches = []
        }
        if descriptor.semanticMatchPolicy == .automatic, semanticMatches.count == 1,
           let match = semanticMatches.first {
            return .resolved(scopeID: match.scopeID)
        }
        if !semanticMatches.isEmpty {
            return .requiresSelection(existing: sorted(semanticMatches), proposedScopeID: newCopyScopeID)
        }
        if let contentHash = descriptor.contentHash {
            let contentMatches = compatible.filter { $0.lastContentHash == contentHash }
            if !contentMatches.isEmpty {
                if descriptor.semanticMatchPolicy == .automatic,
                   let resolution = resolution(forExactMatches: contentMatches, proposedScopeID: newCopyScopeID) {
                    return resolution
                }
                return .requiresSelection(existing: sorted(contentMatches), proposedScopeID: newCopyScopeID)
            }
        }
        return .resolved(scopeID: deterministicScopeID(for: descriptor, aliases: aliases))
    }

    static func revalidate(
        _ intent: ExternalImportSourceClaimIntent,
        latestResolution: ExternalImportSourceResolution,
        descriptor: ExternalImportSourceDescriptor,
        entries: [ExternalImportSourceEntry],
        aliases: SourceAliases
    ) -> ExternalImportSourceClaimResult {
        let requestedScopeID = intent.scopeID
        switch intent {
        case .selectedNew:
            // This is the one intent which deliberately creates a separate identity for a copied
            // source. For bridge exports, registration retains the intrinsic ID as a candidate.
            return .claimed(scopeID: requestedScopeID)

        case .selectedExisting:
            switch latestResolution {
            case .resolved(let canonicalScopeID):
                guard canonicalScopeID != requestedScopeID else {
                    return .claimed(scopeID: requestedScopeID)
                }
                return .requiresRemapping(canonicalScopeID: canonicalScopeID)
            case .requiresSelection(let existing, let proposedScopeID):
                guard existing.contains(where: { $0.scopeID == requestedScopeID }) else {
                    return .requiresSelection(existing: existing, proposedScopeID: proposedScopeID)
                }
                return .claimed(scopeID: requestedScopeID)
            }

        case .resolved:
            switch latestResolution {
            case .resolved(let canonicalScopeID):
                guard canonicalScopeID != requestedScopeID else {
                    return .claimed(scopeID: requestedScopeID)
                }
                return .requiresRemapping(canonicalScopeID: canonicalScopeID)
            case .requiresSelection(let existing, let proposedScopeID):
                // A second review of the exact same bytes can arrive after the first review's
                // claim. Canonicalize it without asking; genuine path replacement stays ambiguous.
                let physicalMatches = matchingPhysicalSource(
                    descriptor: descriptor,
                    entries: entries,
                    aliases: aliases
                )
                if physicalMatches.count == 1, let canonical = physicalMatches.first {
                    guard canonical.scopeID != requestedScopeID else {
                        return .claimed(scopeID: requestedScopeID)
                    }
                    return .requiresRemapping(canonicalScopeID: canonical.scopeID)
                }
                return .requiresSelection(existing: existing, proposedScopeID: proposedScopeID)
            }
        }
    }

    static func registering(
        scopeID: UUID,
        descriptor: ExternalImportSourceDescriptor,
        aliases: SourceAliases,
        importedAt: Date,
        in entries: [ExternalImportSourceEntry]
    ) -> [ExternalImportSourceEntry] {
        let existing = entries.first { $0.scopeID == scopeID }
        let reassignedIntrinsicAlias: UUID?
        if let intrinsicScopeID = descriptor.intrinsicScopeID, intrinsicScopeID != scopeID {
            reassignedIntrinsicAlias = intrinsicScopeID
        } else {
            reassignedIntrinsicAlias = existing?.intrinsicScopeAlias
        }

        var result = entries
        result.removeAll { $0.scopeID == scopeID }
        result.append(ExternalImportSourceEntry(
            scopeID: scopeID,
            format: descriptor.format,
            semanticKey: descriptor.semanticKey,
            fileResourceAlias: aliases.file,
            volumeResourceAlias: aliases.volume,
            lastKnownPathAlias: aliases.path,
            lastContentHash: descriptor.contentHash,
            createdAt: existing?.createdAt ?? importedAt,
            lastImportedAt: importedAt,
            intrinsicScopeAlias: reassignedIntrinsicAlias
        ))
        result.sort { $0.scopeID.uuidString < $1.scopeID.uuidString }
        return result
    }

    static func write(_ entries: [ExternalImportSourceEntry], to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try encodedIndex(entries).write(to: url, options: .atomic)
    }

    static func matchingPhysicalSource(
        descriptor: ExternalImportSourceDescriptor,
        entries: [ExternalImportSourceEntry],
        aliases: SourceAliases
    ) -> [ExternalImportSourceEntry] {
        let compatible = entries.filter { isCompatible($0, with: descriptor) }
        let exactFiles = exactFileMatches(in: compatible, aliases: aliases)
        guard exactFiles.isEmpty else { return exactFiles }
        guard let contentHash = descriptor.contentHash else { return [] }
        return compatible.filter {
            $0.lastKnownPathAlias == aliases.path && $0.lastContentHash == contentHash
        }
    }

    static func exactFileMatches(
        in entries: [ExternalImportSourceEntry],
        aliases: SourceAliases
    ) -> [ExternalImportSourceEntry] {
        entries.filter {
            guard let requested = aliases.file, let existing = $0.fileResourceAlias,
                  requested == existing else { return false }
            guard let requestedVolume = aliases.volume,
                  let existingVolume = $0.volumeResourceAlias else { return true }
            return requestedVolume == existingVolume
        }
    }

    static func sorted(_ entries: [ExternalImportSourceEntry]) -> [ExternalImportSourceEntry] {
        entries.sorted { lhs, rhs in
            if lhs.lastImportedAt != rhs.lastImportedAt {
                return lhs.lastImportedAt > rhs.lastImportedAt
            }
            return lhs.scopeID.uuidString < rhs.scopeID.uuidString
        }
    }

    static func mergingByScope(
        _ first: [ExternalImportSourceEntry],
        _ second: [ExternalImportSourceEntry]
    ) -> [ExternalImportSourceEntry] {
        var entries: [UUID: ExternalImportSourceEntry] = [:]
        for entry in first + second {
            guard let existing = entries[entry.scopeID] else {
                entries[entry.scopeID] = entry
                continue
            }
            if entry.lastImportedAt > existing.lastImportedAt {
                entries[entry.scopeID] = entry
            }
        }
        return Array(entries.values)
    }

    /// First allocation must converge even when two devices have not yet synchronized their source
    /// indexes. A deliberate "new copy" choice still receives the random proposal supplied above.
    static func deterministicScopeID(
        for descriptor: ExternalImportSourceDescriptor,
        aliases: SourceAliases
    ) -> UUID {
        if let intrinsicScopeID = descriptor.intrinsicScopeID {
            return intrinsicScopeID
        }

        let format = boundedIdentityComponent(descriptor.format)
        let identityComponent: String
        if let semanticKey = descriptor.semanticKey, !semanticKey.isEmpty {
            identityComponent = "semantic:\(boundedIdentityComponent(semanticKey))"
        } else if let contentHash = descriptor.contentHash, !contentHash.isEmpty {
            identityComponent = "fingerprint:\(boundedIdentityComponent(contentHash))"
        } else if let fileAlias = aliases.file {
            let volumeAlias = aliases.volume.map(boundedIdentityComponent) ?? "unknown-volume"
            identityComponent = "physical:\(volumeAlias):\(boundedIdentityComponent(fileAlias))"
        } else {
            identityComponent = "path:\(boundedIdentityComponent(aliases.path))"
        }
        return FoundryRuleIdentity.uuid(
            for: "external-import-source:v1#\(format)#\(identityComponent)"
        )
    }

    /// Avoid allowing malformed metadata to create an unbounded canonical identity key while still
    /// distinguishing ordinary long values by length and both ends of the value.
    static func boundedIdentityComponent(_ value: String) -> String {
        let limit = 512
        guard value.count > limit else { return value }
        let half = limit / 2
        return "\(value.prefix(half))#length:\(value.count)#\(value.suffix(half))"
    }

    static func resolution(
        forExactMatches matches: [ExternalImportSourceEntry],
        proposedScopeID: UUID
    ) -> ExternalImportSourceResolution? {
        if matches.count == 1, let match = matches.first {
            return .resolved(scopeID: match.scopeID)
        }
        guard !matches.isEmpty else { return nil }
        return .requiresSelection(
            existing: sorted(matches),
            proposedScopeID: proposedScopeID
        )
    }

    static func isCompatible(
        _ entry: ExternalImportSourceEntry,
        with descriptor: ExternalImportSourceDescriptor
    ) -> Bool {
        guard entry.format == descriptor.format else { return false }
        guard let requestedKey = descriptor.semanticKey, let existingKey = entry.semanticKey else {
            return true
        }
        return requestedKey == existingKey
    }

    static func aliases(for url: URL) -> SourceAliases {
        let hasSecurityScope = url.startAccessingSecurityScopedResource()
        defer { if hasSecurityScope { url.stopAccessingSecurityScopedResource() } }
        // URL resource values may remain cached on a reused security-scoped URL even after the
        // file at that path has been removed and replaced. Resolve metadata through a fresh file
        // URL so a replacement cannot inherit the previous file's physical identity and silently
        // update an unrelated arbitrary import.
        let metadataURL = URL(filePath: url.path)
        let values = try? metadataURL.resourceValues(forKeys: [
            .fileResourceIdentifierKey,
            .volumeIdentifierKey,
        ])
        return SourceAliases(
            file: opaqueAlias(values?.fileResourceIdentifier),
            volume: opaqueAlias(values?.volumeIdentifier),
            path: url.standardizedFileURL.resolvingSymlinksInPath().path
        )
    }

    static func opaqueAlias(_ value: Any?) -> String? {
        guard let value else { return nil }
        if let data = value as? Data { return "data:\(data.base64EncodedString())" }
        if let string = value as? String { return "string:\(string)" }
        if let number = value as? NSNumber { return "number:\(number.stringValue)" }
        if let secureValue = value as? (any NSSecureCoding),
           let data = try? NSKeyedArchiver.archivedData(
               withRootObject: secureValue,
               requiringSecureCoding: true
           ) {
            return "archive:\(data.base64EncodedString())"
        }
        return "description:\(String(reflecting: type(of: value))):\(String(describing: value))"
    }
}
