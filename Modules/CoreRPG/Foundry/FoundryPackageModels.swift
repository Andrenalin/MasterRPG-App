// @copyright André Trettin

import CryptoKit
import Foundation
import Synchronization

// The package, manifest and resource models, split out of FoundryRuleModels.swift. See CODE_AUDIT_29 §9.9.

public struct FoundrySystemManifest: Codable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let description: String?
    public let version: String
    public let compatibility: FoundryCompatibility
    public let packs: [FoundryPackManifest]
    public let rawData: FoundryJSONValue

    public init(
        id: String,
        title: String,
        description: String?,
        version: String,
        compatibility: FoundryCompatibility,
        packs: [FoundryPackManifest],
        rawData: FoundryJSONValue
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.version = version
        self.compatibility = compatibility
        self.packs = packs
        self.rawData = rawData
    }
}

public struct FoundryCompatibility: Codable, Equatable, Sendable {
    public let minimum: String?
    public let verified: String?
    public let maximum: String?

    public init(minimum: String?, verified: String?, maximum: String?) {
        self.minimum = minimum
        self.verified = verified
        self.maximum = maximum
    }
}

public struct FoundryPackManifest: Codable, Equatable, Identifiable, Sendable {
    public var id: String { name }

    public let name: String
    public let label: String
    public let path: String
    public let documentType: String
    public let systemId: String?

    public init(name: String, label: String, path: String, documentType: String, systemId: String?) {
        self.name = name
        self.label = label
        self.path = path
        self.documentType = documentType
        self.systemId = systemId
    }

    /// The archived and sent keys keep their `ID` spelling; the properties follow the
    /// project's `Id` casing. See CODE_AUDIT_29 §4.3.
    private enum CodingKeys: String, CodingKey {
        case name
        case label
        case path
        case documentType
        case systemId = "systemID"
    }
}

public struct FoundryRulePackage: Codable, Equatable, Sendable {
    public static let currentFormatVersion = 1

    public let formatVersion: Int
    public let sourceSHA256: String?
    public let manifest: FoundrySystemManifest
    public let manifestPath: String
    public let templatePath: String?
    public let templateData: FoundryJSONValue?
    public let schemas: [FoundryRuleSchema]
    public let compendiums: [FoundryCompendium]
    public let localizations: [FoundryLocalizationCatalog]
    public let assetPaths: [String]
    public let resources: [FoundryPackageResource]
    public let licensePaths: [String]
    public let licenseDocuments: [FoundryPackageTextResource]
    public let diagnostics: [FoundryImportDiagnostic]

    public init(
        formatVersion: Int = Self.currentFormatVersion,
        sourceSHA256: String? = nil,
        manifest: FoundrySystemManifest,
        manifestPath: String,
        templatePath: String?,
        templateData: FoundryJSONValue?,
        schemas: [FoundryRuleSchema],
        compendiums: [FoundryCompendium],
        localizations: [FoundryLocalizationCatalog] = [],
        assetPaths: [String],
        resources: [FoundryPackageResource] = [],
        licensePaths: [String],
        licenseDocuments: [FoundryPackageTextResource] = [],
        diagnostics: [FoundryImportDiagnostic]
    ) {
        self.formatVersion = formatVersion
        self.sourceSHA256 = sourceSHA256
        self.manifest = manifest
        self.manifestPath = manifestPath
        self.templatePath = templatePath
        self.templateData = templateData
        self.schemas = schemas
        self.compendiums = compendiums
        self.localizations = localizations
        self.assetPaths = assetPaths
        self.resources = resources
        self.licensePaths = licensePaths
        self.licenseDocuments = licenseDocuments
        self.diagnostics = diagnostics
    }

    public var rules: [FoundryRuleDefinition] {
        compendiums.flatMap(\.rules)
    }

    public var ruleCount: Int {
        compendiums.reduce(into: 0) { count, compendium in
            count += compendium.rules.count
        }
    }
}

/// Describes where a rule-referenced file came from without retaining a live file URL.
///
/// Packaged resources can be reopened through `FoundrySystemPackageReader`. Other locations are
/// retained so RuleRPG can report or deliberately resolve external dependencies.
public struct FoundryPackageResource: Codable, Equatable, Hashable, Identifiable, Sendable {
    public enum Location: String, Codable, Equatable, Hashable, Sendable {
        case packaged
        case foundryInstallation
        case remote
        case unresolved
    }

    public var id: String { "\(location.rawValue):\(logicalPath):\(packagePath ?? "-")" }

    public let logicalPath: String
    public let packagePath: String?
    public let location: Location
    public let byteCount: Int?
    public let sha256: String?

    public init(
        logicalPath: String,
        packagePath: String?,
        location: Location,
        byteCount: Int?,
        sha256: String?
    ) {
        self.logicalPath = logicalPath
        self.packagePath = packagePath
        self.location = location
        self.byteCount = byteCount
        self.sha256 = sha256
    }
}

public struct FoundryPackageResourceData: Equatable, Sendable {
    public let resource: FoundryPackageResource
    public let data: Data

    public init(resource: FoundryPackageResource, data: Data) {
        self.resource = resource
        self.data = data
    }
}

public struct FoundryLocalizationCatalog: Codable, Equatable, Identifiable, Sendable {
    public var id: String { languageCode }

    public let languageCode: String
    public let name: String
    public let path: String
    public let translations: FoundryJSONValue

    public init(languageCode: String, name: String, path: String, translations: FoundryJSONValue) {
        self.languageCode = languageCode
        self.name = name
        self.path = path
        self.translations = translations
    }
}

public struct FoundryPackageTextResource: Codable, Equatable, Identifiable, Sendable {
    public var id: String { path }

    public let path: String
    public let content: String

    public init(path: String, content: String) {
        self.path = path
        self.content = content
    }
}

public struct FoundryCompendium: Codable, Equatable, Identifiable, Sendable {
    public var id: String { manifest.name }

    public let manifest: FoundryPackManifest
    public let rules: [FoundryRuleDefinition]
    public let folders: [FoundryFolder]

    public init(manifest: FoundryPackManifest, rules: [FoundryRuleDefinition], folders: [FoundryFolder]) {
        self.manifest = manifest
        self.rules = rules
        self.folders = folders
    }
}

public struct FoundryFolder: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let parentId: String?
    public let sort: Int64?

    public init(id: String, name: String, parentId: String?, sort: Int64?) {
        self.id = id
        self.name = name
        self.parentId = parentId
        self.sort = sort
    }

    /// The archived and sent keys keep their `ID` spelling; the properties follow the
    /// project's `Id` casing. See CODE_AUDIT_29 §4.3.
    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case parentId = "parentID"
        case sort
    }
}
