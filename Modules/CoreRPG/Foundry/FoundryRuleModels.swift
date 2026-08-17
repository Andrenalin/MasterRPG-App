// @copyright André Trettin

import CryptoKit
import Foundation

/// A lossless, concurrency-safe representation of a value stored in a Foundry document.
///
/// `RuleRPG` can persist or map these values without depending on a specific Foundry game
/// system's Swift types.
public enum FoundryJSONValue: Codable, Equatable, Sendable {
    case object([String: FoundryJSONValue])
    case array([FoundryJSONValue])
    case string(String)
    case integer(Int64)
    case unsignedInteger(UInt64)
    case number(Double)
    case bool(Bool)
    case null

    /// A ~200 KB payload of ~100,000 nested arrays (`[[[[[…]]]]]`) — well under any
    /// per-entry size cap — would otherwise recurse one native stack frame per level
    /// during decode and crash the process via stack overflow. See CODE_AUDIT §5.9.
    static let maximumNestingDepth = 128

    public init(from decoder: any Decoder) throws {
        let depthCounter = decoder.userInfo[.masterRPGFoundryJSONDepth] as? FoundryJSONDepthCounter
        depthCounter?.depth += 1
        defer { depthCounter?.depth -= 1 }
        if let depthCounter, depthCounter.depth > Self.maximumNestingDepth {
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "Foundry JSON nesting exceeds the maximum supported depth of \(Self.maximumNestingDepth)."
            ))
        }

        if decoder.userInfo[.masterRPGFoundrySourceJSON] as? Bool != true,
           let taggedContainer = try? decoder.container(keyedBy: FoundryJSONCodingKey.self),
           Set(taggedContainer.allKeys.map(\.stringValue)) == FoundryJSONCodingKey.numericKeys,
           let numericType = try? taggedContainer.decode(
               FoundryJSONNumericType.self,
               forKey: .numericType
           ) {
            switch numericType {
            case .integer:
                self = .integer(try taggedContainer.decode(Int64.self, forKey: .numericValue))
            case .unsignedInteger:
                self = .unsignedInteger(try taggedContainer.decode(UInt64.self, forKey: .numericValue))
            case .number:
                self = .number(try taggedContainer.decode(Double.self, forKey: .numericValue))
            }
            return
        }

        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int64.self) {
            self = .integer(value)
        } else if let value = try? container.decode(UInt64.self) {
            self = .unsignedInteger(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([FoundryJSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: FoundryJSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported Foundry JSON value")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        switch self {
        case .object(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .array(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .string(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .integer(let value):
            var container = encoder.container(keyedBy: FoundryJSONCodingKey.self)
            try container.encode(FoundryJSONNumericType.integer, forKey: .numericType)
            try container.encode(value, forKey: .numericValue)
        case .unsignedInteger(let value):
            var container = encoder.container(keyedBy: FoundryJSONCodingKey.self)
            try container.encode(FoundryJSONNumericType.unsignedInteger, forKey: .numericType)
            try container.encode(value, forKey: .numericValue)
        case .number(let value):
            var container = encoder.container(keyedBy: FoundryJSONCodingKey.self)
            try container.encode(FoundryJSONNumericType.number, forKey: .numericType)
            try container.encode(value, forKey: .numericValue)
        case .bool(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .null:
            var container = encoder.singleValueContainer()
            try container.encodeNil()
        }
    }

    public var objectValue: [String: FoundryJSONValue]? {
        guard case .object(let value) = self else { return nil }
        return value
    }

    public var arrayValue: [FoundryJSONValue]? {
        guard case .array(let value) = self else { return nil }
        return value
    }

    public var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    public var integerValue: Int64? {
        switch self {
        case .integer(let value): value
        case .unsignedInteger(let value): Int64(exactly: value)
        case .number(let value) where value.rounded() == value: Int64(exactly: value)
        default: nil
        }
    }

    public var boolValue: Bool? {
        guard case .bool(let value) = self else { return nil }
        return value
    }

    public subscript(key: String) -> FoundryJSONValue? {
        objectValue?[key]
    }

    public func value(at path: String) -> FoundryJSONValue? {
        value(at: path.split(separator: ".").map(String.init))
    }

    public func value(at path: [String]) -> FoundryJSONValue? {
        path.reduce(Optional(self)) { value, component in
            value?[component]
        }
    }
}

extension CodingUserInfoKey {
    static let masterRPGFoundrySourceJSON = Self(
        rawValue: "de.andretrettin.MasterRPG.decodeFoundrySourceJSON"
    )!
    static let masterRPGFoundryJSONDepth = Self(
        rawValue: "de.andretrettin.MasterRPG.decodeFoundryJSONDepth"
    )!
}

/// Recursion-depth counter threaded through a `JSONDecoder`'s `userInfo` so
/// `FoundryJSONValue.init(from:)` can bound its own nesting. Codable hands each
/// nested array/object element its own fresh `Decoder`/`init(from:)` call, so a
/// plain local variable can't observe depth across those calls — `userInfo` is
/// the only channel threaded through the whole recursive decode, and it needs a
/// reference type since `Decoder` only exposes it for reading.
// @unchecked Sendable: confined to a single, single-threaded `JSONDecoder.decode(_:from:)`
// call — a fresh instance is created per decode and never shared across threads or retained
// beyond it, so its unsynchronized mutable `depth` never actually races. See CODE_AUDIT §3.5.
final class FoundryJSONDepthCounter: @unchecked Sendable {
    var depth = 0
}

private enum FoundryJSONNumericType: String, Codable {
    case integer
    case unsignedInteger
    case number
}

private struct FoundryJSONCodingKey: CodingKey, Hashable {
    static let numericType = Self(stringValue: "__masterRPGFoundryNumericType")
    static let numericValue = Self(stringValue: "__masterRPGFoundryNumericValue")
    static let numericKeys = Set([numericType.stringValue, numericValue.stringValue])

    let stringValue: String
    let intValue: Int?

    init(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }
}

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
    public let systemID: String?

    public init(name: String, label: String, path: String, documentType: String, systemID: String?) {
        self.name = name
        self.label = label
        self.path = path
        self.documentType = documentType
        self.systemID = systemID
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
    public let parentID: String?
    public let sort: Int64?

    public init(id: String, name: String, parentID: String?, sort: Int64?) {
        self.id = id
        self.name = name
        self.parentID = parentID
        self.sort = sort
    }
}

/// A lossless rule document with a small amount of system-independent interpretation.
public struct FoundryRuleDefinition: Codable, Equatable, Identifiable, Sendable {
    /// Stable across repeated imports of the same Foundry compendium.
    public let id: String
    public let documentID: String
    public let packName: String
    public let documentType: String
    public let subtype: String
    public let category: FoundryRuleCategory
    public let name: String
    public let descriptionHTML: String?
    public let imagePath: String?
    public let folderID: String?
    public let values: [FoundryRuleValue]
    public let tags: [String]
    public let references: [FoundryRuleReference]
    public let embeddedRules: [FoundryEmbeddedRule]
    public let effects: [FoundryRuleEffect]
    public let rawData: FoundryJSONValue

    /// A deterministic UUID suitable for a Core Data `RuleRPG` identity.
    public var masterRPGID: UUID { FoundryRuleIdentity.uuid(for: id) }

    public init(
        id: String,
        documentID: String,
        packName: String,
        documentType: String,
        subtype: String,
        category: FoundryRuleCategory,
        name: String,
        descriptionHTML: String?,
        imagePath: String?,
        folderID: String?,
        values: [FoundryRuleValue],
        tags: [String],
        references: [FoundryRuleReference],
        embeddedRules: [FoundryEmbeddedRule],
        effects: [FoundryRuleEffect],
        rawData: FoundryJSONValue
    ) {
        self.id = id
        self.documentID = documentID
        self.packName = packName
        self.documentType = documentType
        self.subtype = subtype
        self.category = category
        self.name = name
        self.descriptionHTML = descriptionHTML
        self.imagePath = imagePath
        self.folderID = folderID
        self.values = values
        self.tags = tags
        self.references = references
        self.embeddedRules = embeddedRules
        self.effects = effects
        self.rawData = rawData
    }
}

public struct FoundryEmbeddedRule: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let subtype: String
    public let category: FoundryRuleCategory
    public let descriptionHTML: String?
    public let imagePath: String?
    public let values: [FoundryRuleValue]
    public let references: [FoundryRuleReference]
    public let effects: [FoundryRuleEffect]
    public let rawData: FoundryJSONValue

    public var masterRPGID: UUID { FoundryRuleIdentity.uuid(for: id) }

    public init(
        id: String,
        name: String,
        subtype: String,
        category: FoundryRuleCategory,
        descriptionHTML: String?,
        imagePath: String?,
        values: [FoundryRuleValue],
        references: [FoundryRuleReference],
        effects: [FoundryRuleEffect],
        rawData: FoundryJSONValue
    ) {
        self.id = id
        self.name = name
        self.subtype = subtype
        self.category = category
        self.descriptionHTML = descriptionHTML
        self.imagePath = imagePath
        self.values = values
        self.references = references
        self.effects = effects
        self.rawData = rawData
    }
}

/// An extensible category. Unknown game systems retain their original subtype instead of losing data.
public struct FoundryRuleCategory: Codable, Equatable, Hashable, RawRepresentable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let character = Self(rawValue: "character")
    public static let creature = Self(rawValue: "creature")
    public static let spell = Self(rawValue: "spell")
    public static let talent = Self(rawValue: "talent")
    public static let weapon = Self(rawValue: "weapon")
    public static let armor = Self(rawValue: "armor")
    public static let shield = Self(rawValue: "shield")
    public static let equipment = Self(rawValue: "equipment")
    public static let loot = Self(rawValue: "loot")
    public static let ancestryAbility = Self(rawValue: "ancestryAbility")
    public static let language = Self(rawValue: "language")
    public static let script = Self(rawValue: "script")
    public static let creatureAbility = Self(rawValue: "creatureAbility")
}

public struct FoundryRuleValue: Codable, Equatable, Identifiable, Sendable {
    public var id: String { path }

    public let path: String
    public let value: FoundryJSONValue

    public init(path: String, value: FoundryJSONValue) {
        self.path = path
        self.value = value
    }
}

public struct FoundryRuleSchema: Codable, Equatable, Identifiable, Sendable {
    public var id: String { "\(documentType).\(subtype)" }

    public let documentType: String
    public let subtype: String
    public let inheritedTemplates: [String]
    public let fields: [FoundryRuleField]
    public let rawData: FoundryJSONValue

    public init(
        documentType: String,
        subtype: String,
        inheritedTemplates: [String],
        fields: [FoundryRuleField],
        rawData: FoundryJSONValue
    ) {
        self.documentType = documentType
        self.subtype = subtype
        self.inheritedTemplates = inheritedTemplates
        self.fields = fields
        self.rawData = rawData
    }
}

public struct FoundryRuleField: Codable, Equatable, Identifiable, Sendable {
    public enum ValueKind: String, Codable, Equatable, Sendable {
        case object
        case array
        case string
        case integer
        case unsignedInteger
        case number
        case boolean
        case null
    }

    public var id: String { path }

    public let path: String
    public let valueKind: ValueKind
    public let defaultValue: FoundryJSONValue

    public init(path: String, valueKind: ValueKind, defaultValue: FoundryJSONValue) {
        self.path = path
        self.valueKind = valueKind
        self.defaultValue = defaultValue
    }
}

public struct FoundryRuleReference: Codable, Equatable, Hashable, Sendable {
    public enum Kind: String, Codable, Equatable, Sendable {
        case compendium
        case uuid
        case document
    }

    public let kind: Kind
    public let sourcePath: String
    public let rawToken: String
    public let target: String
    public let label: String?
    public let packName: String?
    public let documentID: String?

    public init(
        kind: Kind,
        sourcePath: String,
        rawToken: String,
        target: String,
        label: String?,
        packName: String?,
        documentID: String?
    ) {
        self.kind = kind
        self.sourcePath = sourcePath
        self.rawToken = rawToken
        self.target = target
        self.label = label
        self.packName = packName
        self.documentID = documentID
    }
}

public struct FoundryRuleEffect: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let isDisabled: Bool
    public let transfersToActor: Bool
    public let statuses: [String]
    public let changes: [FoundryRuleEffectChange]
    public let duration: FoundryJSONValue?
    public let rawData: FoundryJSONValue

    public var masterRPGID: UUID { FoundryRuleIdentity.uuid(for: id) }

    public init(
        id: String,
        name: String,
        isDisabled: Bool,
        transfersToActor: Bool,
        statuses: [String],
        changes: [FoundryRuleEffectChange],
        duration: FoundryJSONValue?,
        rawData: FoundryJSONValue
    ) {
        self.id = id
        self.name = name
        self.isDisabled = isDisabled
        self.transfersToActor = transfersToActor
        self.statuses = statuses
        self.changes = changes
        self.duration = duration
        self.rawData = rawData
    }
}

public struct FoundryRuleEffectChange: Codable, Equatable, Sendable {
    public let path: String
    public let mode: Int64
    public let operand: FoundryJSONValue
    public let priority: Int64?

    public init(path: String, mode: Int64, operand: FoundryJSONValue, priority: Int64?) {
        self.path = path
        self.mode = mode
        self.operand = operand
        self.priority = priority
    }
}

public enum FoundryRuleIdentity {
    /// Generates an RFC-compatible, deterministic version-8 UUID from a canonical source key.
    public static func uuid(for canonicalKey: String) -> UUID {
        var bytes = Array(SHA256.hash(data: Data(canonicalKey.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x80
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}

public struct FoundryImportDiagnostic: Codable, Equatable, Identifiable, Sendable {
    public enum Severity: String, Codable, Equatable, Sendable {
        case information
        case warning
    }

    public var id: String { "\(code):\(packName ?? "package"): \(message)" }

    public let severity: Severity
    public let code: String
    public let message: String
    public let packName: String?

    public init(severity: Severity, code: String, message: String, packName: String? = nil) {
        self.severity = severity
        self.code = code
        self.message = message
        self.packName = packName
    }
}

public struct FoundryImportLimits: Equatable, Sendable {
    public static let `default` = Self()

    public let maximumArchiveSize: Int
    public let maximumEntrySize: Int
    public let maximumRuleDataSize: Int
    public let maximumResourceBatchSize: Int
    public let maximumDocumentCount: Int
    /// Bounds newline-delimited transport records, including tombstones and malformed records.
    public let maximumRecordCount: Int
    /// Bounds warnings created from repeated malformed or forward-versioned records.
    public let maximumDiagnosticCount: Int
    public let maximumUniversalVTTElementCount: Int
    public let maximumUniversalVTTCoordinateMagnitude: Double
    public let maximumUniversalVTTPixelDimension: Double

    public init(
        maximumArchiveSize: Int = 1_073_741_824,
        maximumEntrySize: Int = 67_108_864,
        maximumRuleDataSize: Int = 536_870_912,
        maximumResourceBatchSize: Int = 536_870_912,
        maximumDocumentCount: Int = 100_000,
        maximumRecordCount: Int = 400_000,
        maximumDiagnosticCount: Int = 1_000,
        maximumUniversalVTTElementCount: Int = 1_000_000,
        maximumUniversalVTTCoordinateMagnitude: Double = 1_000_000,
        maximumUniversalVTTPixelDimension: Double = 1_000_000
    ) {
        self.maximumArchiveSize = maximumArchiveSize
        self.maximumEntrySize = maximumEntrySize
        self.maximumRuleDataSize = maximumRuleDataSize
        self.maximumResourceBatchSize = maximumResourceBatchSize
        self.maximumDocumentCount = maximumDocumentCount
        self.maximumRecordCount = maximumRecordCount
        self.maximumDiagnosticCount = maximumDiagnosticCount
        self.maximumUniversalVTTElementCount = maximumUniversalVTTElementCount
        self.maximumUniversalVTTCoordinateMagnitude = maximumUniversalVTTCoordinateMagnitude
        self.maximumUniversalVTTPixelDimension = maximumUniversalVTTPixelDimension
    }
}

public enum FoundryImportError: Error, Equatable, LocalizedError, Sendable {
    case fileTooLarge(Int)
    case invalidArchive(String)
    case encryptedArchive
    case unsupportedZIPCompression(UInt16)
    case unsupportedLevelDBCompression(UInt8)
    case unsupportedLevelDBLog(String)
    case unsupportedLevelDBTableSet(pack: String, tableCount: Int)
    case corruptLevelDB(String)
    case missingManifest
    case ambiguousManifest
    case invalidManifest(String)
    case invalidDocument(pack: String, key: String)
    case missingPack(String)
    case tooManyDocuments(Int)
    case tooManyUniversalVTTElements(Int)
    case resourceUnavailable(String)
    case duplicateResourceRequest
    case sourceMismatch
    case resourceIntegrityFailure(String)
    case bareManifestRequiresContainer(String)
    case unsupportedSource

    public var errorDescription: String? {
        switch self {
        case .fileTooLarge(let size):
            "The Foundry package is too large (\(size) bytes)."
        case .invalidArchive(let reason):
            "The Foundry ZIP archive is invalid: \(reason)"
        case .encryptedArchive:
            "Encrypted ZIP archives are not supported."
        case .unsupportedZIPCompression(let method):
            "ZIP compression method \(method) is not supported."
        case .unsupportedLevelDBCompression(let method):
            "LevelDB compression method \(method) is not supported."
        case .unsupportedLevelDBLog(let path):
            "The mutable LevelDB log \(path) contains data that cannot be imported safely. Compact the Foundry pack first."
        case .unsupportedLevelDBTableSet(let pack, let tableCount):
            "The Foundry compendium \(pack) contains \(tableCount) LevelDB tables. Import currently requires a compacted pack with exactly one table."
        case .corruptLevelDB(let reason):
            "The Foundry compendium database is corrupt: \(reason)"
        case .missingManifest:
            "The package does not contain a supported Foundry manifest."
        case .ambiguousManifest:
            "The package contains more than one equally likely Foundry manifest."
        case .invalidManifest(let reason):
            "The Foundry package manifest is invalid: \(reason)"
        case .invalidDocument(let pack, let key):
            "The Foundry compendium \(pack) contains an invalid document at \(key)."
        case .missingPack(let name):
            "The Foundry compendium \(name) is missing."
        case .tooManyDocuments(let count):
            "The Foundry package contains too many documents (\(count))."
        case .tooManyUniversalVTTElements(let count):
            "The Universal VTT map contains too many geometry elements (\(count))."
        case .resourceUnavailable(let path):
            "The Foundry resource \(path) is not packaged in the selected artifact."
        case .duplicateResourceRequest:
            "A Foundry resource was requested more than once in the same batch."
        case .sourceMismatch:
            "The selected Foundry source does not match the package that was inspected."
        case .resourceIntegrityFailure(let path):
            "The Foundry resource \(path) changed or failed its integrity check."
        case .bareManifestRequiresContainer(let filename):
            "Select the folder or ZIP package containing \(filename), not the manifest file by itself."
        case .unsupportedSource:
            "Select a supported Foundry package, document export, database, bridge file, or Universal VTT map."
        }
    }
}
