// @copyright André Trettin

import CryptoKit
import Foundation
import Synchronization

/// A lossless rule document with a small amount of system-independent interpretation.
public struct FoundryRuleDefinition: Codable, Equatable, Identifiable, Sendable {
    /// Stable across repeated imports of the same Foundry compendium.
    public let id: String
    public let documentId: String
    public let packName: String
    public let documentType: String
    public let subtype: String
    public let category: FoundryRuleCategory
    public let name: String
    public let descriptionHTML: String?
    public let imagePath: String?
    public let folderId: String?
    public let values: [FoundryRuleValue]
    public let tags: [String]
    public let references: [FoundryRuleReference]
    public let embeddedRules: [FoundryEmbeddedRule]
    public let effects: [FoundryRuleEffect]
    public let rawData: FoundryJSONValue

    /// A deterministic UUID suitable for a Core Data `RuleRPG` identity.
    public var masterRPGId: UUID { FoundryRuleIdentity.uuid(for: id) }

    public init(
        id: String,
        documentId: String,
        packName: String,
        documentType: String,
        subtype: String,
        category: FoundryRuleCategory,
        name: String,
        descriptionHTML: String?,
        imagePath: String?,
        folderId: String?,
        values: [FoundryRuleValue],
        tags: [String],
        references: [FoundryRuleReference],
        embeddedRules: [FoundryEmbeddedRule],
        effects: [FoundryRuleEffect],
        rawData: FoundryJSONValue
    ) {
        self.id = id
        self.documentId = documentId
        self.packName = packName
        self.documentType = documentType
        self.subtype = subtype
        self.category = category
        self.name = name
        self.descriptionHTML = descriptionHTML
        self.imagePath = imagePath
        self.folderId = folderId
        self.values = values
        self.tags = tags
        self.references = references
        self.embeddedRules = embeddedRules
        self.effects = effects
        self.rawData = rawData
    }

    /// The archived and sent keys keep their `ID` spelling; the properties follow the
    /// project's `Id` casing. See CODE_AUDIT_29 §4.3.
    private enum CodingKeys: String, CodingKey {
        case id
        case documentId = "documentID"
        case packName
        case documentType
        case subtype
        case category
        case name
        case descriptionHTML
        case imagePath
        case folderId = "folderID"
        case values
        case tags
        case references
        case embeddedRules
        case effects
        case rawData
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

    public var masterRPGId: UUID { FoundryRuleIdentity.uuid(for: id) }

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

    /// The archived and sent keys keep their `ID` spelling; the properties follow the
    /// project's `Id` casing. See CODE_AUDIT_29 §4.3.
    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case subtype
        case category
        case descriptionHTML
        case imagePath
        case values
        case references
        case effects
        case rawData
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
    public let documentId: String?

    public init(
        kind: Kind,
        sourcePath: String,
        rawToken: String,
        target: String,
        label: String?,
        packName: String?,
        documentId: String?
    ) {
        self.kind = kind
        self.sourcePath = sourcePath
        self.rawToken = rawToken
        self.target = target
        self.label = label
        self.packName = packName
        self.documentId = documentId
    }

    /// The archived and sent keys keep their `ID` spelling; the properties follow the
    /// project's `Id` casing. See CODE_AUDIT_29 §4.3.
    private enum CodingKeys: String, CodingKey {
        case kind
        case sourcePath
        case rawToken
        case target
        case label
        case packName
        case documentId = "documentID"
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

    public var masterRPGId: UUID { FoundryRuleIdentity.uuid(for: id) }

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

    /// The archived and sent keys keep their `ID` spelling; the properties follow the
    /// project's `Id` casing. See CODE_AUDIT_29 §4.3.
    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case isDisabled
        case transfersToActor
        case statuses
        case changes
        case duration
        case rawData
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
        DeterministicUUID.uuid(hashing: canonicalKey, version: .v8)
    }
}

