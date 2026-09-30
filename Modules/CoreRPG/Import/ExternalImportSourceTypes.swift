// @copyright André Trettin

import Foundation

// The value types of `ExternalImportSourceRegistry`, split out of its file — see CODE_AUDIT_19 §9.23.

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
