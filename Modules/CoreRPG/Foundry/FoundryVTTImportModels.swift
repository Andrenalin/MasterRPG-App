// @copyright André Trettin

import Foundation

/// The kind of Foundry source selected for import.
public enum FoundryVTTPackageKind: String, Codable, Equatable, Sendable {
    case system
    case module
    case world
    case exportedDocument
    case documentCollection
}

/// An extensible Foundry document name.
///
/// Foundry game systems and modules can add document-like collections. Keeping this a raw-value
/// type means a newer Foundry family is preserved instead of being rejected by an older app.
public struct FoundryDocumentType: RawRepresentable, Codable, Equatable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let unknown = Self(rawValue: "Unknown")
    public static let actor = Self(rawValue: "Actor")
    public static let item = Self(rawValue: "Item")
    public static let scene = Self(rawValue: "Scene")
    public static let level = Self(rawValue: "Level")
    public static let journalEntry = Self(rawValue: "JournalEntry")
    public static let journalEntryPage = Self(rawValue: "JournalEntryPage")
    public static let rollTable = Self(rawValue: "RollTable")
    public static let tableResult = Self(rawValue: "TableResult")
    public static let playlist = Self(rawValue: "Playlist")
    public static let playlistSound = Self(rawValue: "PlaylistSound")
    public static let cards = Self(rawValue: "Cards")
    public static let card = Self(rawValue: "Card")
    public static let adventure = Self(rawValue: "Adventure")
    public static let folder = Self(rawValue: "Folder")
    public static let activeEffect = Self(rawValue: "ActiveEffect")
    public static let token = Self(rawValue: "Token")
    public static let wall = Self(rawValue: "Wall")
    public static let ambientLight = Self(rawValue: "AmbientLight")
    public static let ambientSound = Self(rawValue: "AmbientSound")
    public static let tile = Self(rawValue: "Tile")
    public static let drawing = Self(rawValue: "Drawing")
    public static let note = Self(rawValue: "Note")
    public static let region = Self(rawValue: "Region")
    public static let combat = Self(rawValue: "Combat")
    public static let combatant = Self(rawValue: "Combatant")
    public static let macro = Self(rawValue: "Macro")
    public static let chatMessage = Self(rawValue: "ChatMessage")
    public static let user = Self(rawValue: "User")
}

/// A system-, module-, or world-manifest represented without tying the importer to one schema
/// revision of Foundry VTT.
public struct FoundryVTTPackageManifest: Codable, Equatable, Sendable {
    public let kind: FoundryVTTPackageKind
    public let id: String
    public let title: String
    public let descriptionHTML: String?
    public let version: String?
    public let systemId: String?
    public let compatibility: FoundryCompatibility
    public let rawData: FoundryJSONValue

    public init(
        kind: FoundryVTTPackageKind,
        id: String,
        title: String,
        descriptionHTML: String?,
        version: String?,
        systemId: String?,
        compatibility: FoundryCompatibility,
        rawData: FoundryJSONValue
    ) {
        self.kind = kind
        self.id = id
        self.title = title
        self.descriptionHTML = descriptionHTML
        self.version = version
        self.systemId = systemId
        self.compatibility = compatibility
        self.rawData = rawData
    }

    /// The archived and sent keys keep their `ID` spelling; the properties follow the
    /// project's `Id` casing. See CODE_AUDIT_29 §4.3.
    private enum CodingKeys: String, CodingKey {
        case kind
        case id
        case title
        case descriptionHTML
        case version
        case systemId = "systemID"
        case compatibility
        case rawData
    }
}

/// A folder declaration retained separately from documents so clients can reconstruct hierarchy.
public struct FoundryDocumentFolder: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let documentId: String
    public let name: String
    public let parentId: String?
    public let documentType: FoundryDocumentType
    public let sort: Int64?
    public let rawData: FoundryJSONValue

    public init(
        id: String,
        documentId: String,
        name: String,
        parentId: String?,
        documentType: FoundryDocumentType,
        sort: Int64?,
        rawData: FoundryJSONValue
    ) {
        self.id = id
        self.documentId = documentId
        self.name = name
        self.parentId = parentId
        self.documentType = documentType
        self.sort = sort
        self.rawData = rawData
    }

    /// The archived and sent keys keep their `ID` spelling; the properties follow the
    /// project's `Id` casing. See CODE_AUDIT_29 §4.3.
    private enum CodingKeys: String, CodingKey {
        case id
        case documentId = "documentID"
        case name
        case parentId = "parentID"
        case documentType
        case sort
        case rawData
    }
}

/// A lossless Foundry document plus conservative, system-independent metadata.
public struct FoundryDocument: Codable, Equatable, Identifiable, Sendable {
    /// Stable for repeated imports from the same package/collection/document hierarchy.
    public let id: String
    public let documentId: String
    public let documentType: FoundryDocumentType
    public let subtype: String?
    public let name: String
    public let folderId: String?
    public let sort: Int64?
    public let imagePath: String?
    public let descriptionHTML: String?
    public let parentId: String?
    /// Original Foundry UUID when the source format provides one explicitly.
    public let sourceUUID: String?
    /// Original Foundry parent UUID for bridge records that are exported separately.
    public let sourceParentUUID: String?
    public let embeddedDocuments: [FoundryDocument]
    public let references: [FoundryRuleReference]
    /// Top-level fields not interpreted by the transport. They remain present in `rawData`.
    public let unknownFieldNames: [String]
    public let rawData: FoundryJSONValue

    public var masterRPGId: UUID { FoundryRuleIdentity.uuid(for: id) }

    public init(
        id: String,
        documentId: String,
        documentType: FoundryDocumentType,
        subtype: String?,
        name: String,
        folderId: String?,
        sort: Int64?,
        imagePath: String?,
        descriptionHTML: String?,
        parentId: String?,
        sourceUUID: String? = nil,
        sourceParentUUID: String? = nil,
        embeddedDocuments: [FoundryDocument],
        references: [FoundryRuleReference],
        unknownFieldNames: [String],
        rawData: FoundryJSONValue
    ) {
        self.id = id
        self.documentId = documentId
        self.documentType = documentType
        self.subtype = subtype
        self.name = name
        self.folderId = folderId
        self.sort = sort
        self.imagePath = imagePath
        self.descriptionHTML = descriptionHTML
        self.parentId = parentId
        self.sourceUUID = sourceUUID
        self.sourceParentUUID = sourceParentUUID
        self.embeddedDocuments = embeddedDocuments
        self.references = references
        self.unknownFieldNames = unknownFieldNames
        self.rawData = rawData
    }

    /// The archived and sent keys keep their `ID` spelling; the properties follow the
    /// project's `Id` casing. See CODE_AUDIT_29 §4.3.
    private enum CodingKeys: String, CodingKey {
        case id
        case documentId = "documentID"
        case documentType
        case subtype
        case name
        case folderId = "folderID"
        case sort
        case imagePath
        case descriptionHTML
        case parentId = "parentID"
        case sourceUUID
        case sourceParentUUID
        case embeddedDocuments
        case references
        case unknownFieldNames
        case rawData
    }
}

/// A named database, compendium, or standalone group of Foundry documents.
public struct FoundryDocumentCollection: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let label: String
    public let sourcePath: String
    public let declaredDocumentType: FoundryDocumentType
    public let documents: [FoundryDocument]
    public let folders: [FoundryDocumentFolder]
    public let rawData: FoundryJSONValue?

    public init(
        id: String,
        name: String,
        label: String,
        sourcePath: String,
        declaredDocumentType: FoundryDocumentType,
        documents: [FoundryDocument],
        folders: [FoundryDocumentFolder],
        rawData: FoundryJSONValue? = nil
    ) {
        self.id = id
        self.name = name
        self.label = label
        self.sourcePath = sourcePath
        self.declaredDocumentType = declaredDocumentType
        self.documents = documents
        self.folders = folders
        self.rawData = rawData
    }
}

public struct FoundryVTTImportStatistics: Codable, Equatable, Sendable {
    public let collectionCount: Int
    public let topLevelDocumentCount: Int
    public let embeddedDocumentCount: Int
    public let folderCount: Int
    public let unknownFieldCount: Int
    public let documentCounts: [String: Int]

    public init(
        collectionCount: Int,
        topLevelDocumentCount: Int,
        embeddedDocumentCount: Int,
        folderCount: Int,
        unknownFieldCount: Int,
        documentCounts: [String: Int]
    ) {
        self.collectionCount = collectionCount
        self.topLevelDocumentCount = topLevelDocumentCount
        self.embeddedDocumentCount = embeddedDocumentCount
        self.folderCount = folderCount
        self.unknownFieldCount = unknownFieldCount
        self.documentCounts = documentCounts
    }
}

/// Stable, transport-only output consumed by module-specific import mappers.
public struct FoundryVTTImportPackage: Codable, Equatable, Sendable {
    public static let currentFormatVersion = 1

    public let formatVersion: Int
    public let sourceSHA256: String?
    public let kind: FoundryVTTPackageKind
    public let manifestPath: String?
    public let manifest: FoundryVTTPackageManifest?
    public let collections: [FoundryDocumentCollection]
    public let resources: [FoundryPackageResource]
    public let textResources: [FoundryPackageTextResource]
    public let diagnostics: [FoundryImportDiagnostic]
    public let statistics: FoundryVTTImportStatistics
    /// Present for compatible system packages so RuleRPG can use its normalized mapping API.
    public let rulePackage: FoundryRulePackage?

    public init(
        formatVersion: Int = Self.currentFormatVersion,
        sourceSHA256: String? = nil,
        kind: FoundryVTTPackageKind,
        manifestPath: String?,
        manifest: FoundryVTTPackageManifest?,
        collections: [FoundryDocumentCollection],
        resources: [FoundryPackageResource],
        textResources: [FoundryPackageTextResource] = [],
        diagnostics: [FoundryImportDiagnostic],
        statistics: FoundryVTTImportStatistics,
        rulePackage: FoundryRulePackage? = nil
    ) {
        self.formatVersion = formatVersion
        self.sourceSHA256 = sourceSHA256
        self.kind = kind
        self.manifestPath = manifestPath
        self.manifest = manifest
        self.collections = collections
        self.resources = resources
        self.textResources = textResources
        self.diagnostics = diagnostics
        self.statistics = statistics
        self.rulePackage = rulePackage
    }

    public var documents: [FoundryDocument] {
        collections.flatMap(\.documents)
    }

    public var allDocuments: [FoundryDocument] {
        func flatten(_ document: FoundryDocument) -> [FoundryDocument] {
            [document] + document.embeddedDocuments.flatMap(flatten)
        }
        return documents.flatMap(flatten)
    }

    public var folders: [FoundryDocumentFolder] {
        collections.flatMap(\.folders)
    }
}
