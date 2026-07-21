// @copyright André Trettin

import CoreRPG
import Foundation

/// System and package provenance retained with an imported rule.
///
/// The fields stay editable so manually maintained rule libraries can correct or add
/// provenance without changing the lossless source payload.
public struct RuleSourceMetadata: Codable, Equatable, Hashable, Sendable {
    public init(
        sourceIdentifier: String = "",
        systemID: String = "",
        systemTitle: String = "",
        systemVersion: String = "",
        packageIdentifier: String = "",
        packageName: String = "",
        documentID: String = "",
        documentType: String = "",
        subtype: String = "",
        ruleCategory: String = "",
        imagePath: String = ""
    ) {
        self.sourceIdentifier = sourceIdentifier
        self.systemID = systemID
        self.systemTitle = systemTitle
        self.systemVersion = systemVersion
        self.packageIdentifier = packageIdentifier
        self.packageName = packageName
        self.documentID = documentID
        self.documentType = documentType
        self.subtype = subtype
        self.ruleCategory = ruleCategory
        self.imagePath = imagePath
    }

    public static let empty = RuleSourceMetadata()

    public var sourceIdentifier: String
    public var systemID: String
    public var systemTitle: String
    public var systemVersion: String
    public var packageIdentifier: String
    public var packageName: String
    public var documentID: String
    public var documentType: String
    public var subtype: String
    public var ruleCategory: String
    public var imagePath: String

    public var isEmpty: Bool {
        self == .empty
    }
}

/// The normalized Foundry payload retained independently from the editable presentation.
///
/// `FoundryRuleDefinition` preserves interpreted values, references, embedded rules,
/// effects, and raw JSON. A generic document payload supports Foundry world/module Items
/// that were not read from a system compendium.
public enum RuleSourcePayload: Codable, Equatable, Sendable {
    case foundryRule(FoundryRuleDefinition)
    case foundryDocument(FoundryJSONValue)
}

public enum RuleEntryKind: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case text
    case value
    case reference
    case embeddedRule
    case effect
    case source

    public var localizedTitle: LocalizedStringResource {
        switch self {
        case .text: "Sections"
        case .value: "Values"
        case .reference: "References"
        case .embeddedRule: "Embedded Rules"
        case .effect: "Effects"
        case .source: "Source"
        }
    }
}

