// @copyright André Trettin

import CoreRPG
import Foundation

public extension RuleModel {
    /// Maps a normalized system-compendium rule into an editable RuleRPG model.
    /// The complete `FoundryRuleDefinition` remains available through `sourcePayload`.
    @MainActor
    static func foundry(
        _ rule: FoundryRuleDefinition,
        manifest: FoundrySystemManifest,
        id: UUID? = nil,
        identityNamespace: String? = nil,
        parentId: UUID? = nil
    ) -> RuleModel {
        let metadata = RuleSourceMetadata(
            sourceIdentifier: rule.id,
            systemId: manifest.id,
            systemTitle: FoundryTextDecoder.decodedText(manifest.title),
            systemVersion: manifest.version,
            packageIdentifier: "\(manifest.id).\(rule.packName)",
            packageName: FoundryTextDecoder.decodedText(rule.packName),
            documentId: rule.documentId,
            documentType: FoundryTextDecoder.decodedText(rule.documentType),
            subtype: FoundryTextDecoder.decodedText(rule.subtype),
            ruleCategory: FoundryTextDecoder.decodedText(rule.category.rawValue),
            imagePath: rule.imagePath ?? ""
        )
        let generatedEntries = foundryEntries(
            rule: rule,
            sourceIdentifier: identityNamespace ?? rule.id
        )
        let generatedTags = orderedUnique(
            rule.tags + [rule.category.rawValue, rule.subtype, manifest.title, "Foundry VTT"]
        )

        return RuleModel(
            id: id ?? rule.masterRPGId,
            name: FoundryTextDecoder.decodedText(rule.name),
            description: inertParagraphs(readableText(fromHTML: rule.descriptionHTML)),
            tags: generatedTags,
            category: .rules,
            entries: generatedEntries,
            sourceMetadata: metadata,
            sourcePayload: .foundryRule(rule),
            parentId: parentId
        )
    }

    /// Maps a generic Foundry Item/document projection into RuleRPG while retaining its raw JSON.
    @MainActor
    static func foundryDocument(
        id: UUID,
        name: String,
        descriptionHTML: String?,
        tags: [String],
        documentType: String,
        subtype: String,
        rawData: FoundryJSONValue,
        parentId: UUID?,
        packageIdentifier: String,
        identityNamespace: String? = nil
    ) -> RuleModel {
        let sourceIdentifier = rawData["_id"]?.stringValue ?? id.uuidString.lowercased()
        let systemId = rawData.value(at: "_stats.systemId")?.stringValue ?? ""
        let systemVersion = rawData.value(at: "_stats.systemVersion")?.stringValue ?? ""
        let category = rawData["type"]?.stringValue ?? subtype
        let imagePath = rawData["img"]?.stringValue ?? ""
        let metadata = RuleSourceMetadata(
            sourceIdentifier: sourceIdentifier,
            systemId: systemId,
            systemVersion: systemVersion,
            packageIdentifier: packageIdentifier,
            packageName: FoundryTextDecoder.decodedText(packageIdentifier),
            documentId: sourceIdentifier,
            documentType: FoundryTextDecoder.decodedText(documentType),
            subtype: FoundryTextDecoder.decodedText(subtype),
            ruleCategory: FoundryTextDecoder.decodedText(category),
            imagePath: imagePath
        )
        let values = hierarchicalValues(
            rawData["system"] ?? rawData,
            sourceIdentifier: identityNamespace ?? sourceIdentifier
        )

        return RuleModel(
            id: id,
            name: FoundryTextDecoder.decodedText(name),
            description: inertParagraphs(readableText(fromHTML: descriptionHTML)),
            tags: orderedUnique(tags + [subtype, "Foundry VTT"]),
            category: .rules,
            entries: values,
            sourceMetadata: metadata,
            sourcePayload: .foundryDocument(rawData),
            parentId: parentId
        )
    }

}

extension RuleModel {
    static func foundryEntries(
        rule: FoundryRuleDefinition,
        sourceIdentifier: String
    ) -> [RuleEntryModel] {
        var result = hierarchicalValues(
            projectedRuleValues(rule.values),
            sourceIdentifier: sourceIdentifier
        )

        result.append(contentsOf: rule.references.enumerated().map { index, reference in
            let label = reference.label?.isEmpty == false
                ? FoundryTextDecoder.decodedText(reference.label ?? reference.target)
                : FoundryTextDecoder.decodedText(reference.target)
            var details = "**Target:** \(inert(reference.target))"
            if let packName = reference.packName, !packName.isEmpty {
                details += "\n\n**Pack:** \(inert(FoundryTextDecoder.decodedText(packName)))"
            }
            if let documentId = reference.documentId, !documentId.isEmpty {
                details += "\n\n**Document:** \(inert(documentId))"
            }
            return RuleEntryModel(
                id: FoundryRuleIdentity.uuid(
                    for: "\(sourceIdentifier)#reference#\(reference.sourcePath)#\(index)"
                ),
                name: label,
                content: details,
                kind: .reference
            )
        })

        result.append(contentsOf: rule.embeddedRules.map { embedded in
            var sections = [inertParagraphs(readableText(fromHTML: embedded.descriptionHTML))]
                .filter { !$0.isEmpty }
            let values = embedded.values.map {
                "- **\(inert(FoundryTextDecoder.decodedText($0.path))):** \(inert(presentation($0.value)))"
            }
            if !values.isEmpty {
                sections.append("**Values**\n\(values.joined(separator: "\n"))")
            }
            if !embedded.references.isEmpty {
                let references = embedded.references.enumerated().map { index, reference in
                    foundryReferenceDetails(reference, index: index)
                }
                sections.append("**References**\n\n\(references.joined(separator: "\n\n"))")
            }
            if !embedded.effects.isEmpty {
                let effects = embedded.effects.enumerated().map { index, effect in
                    let name = effect.name.isEmpty
                        ? "Effect \(index + 1)"
                        : FoundryTextDecoder.decodedText(effect.name)
                    return "**\(inert(name))**\n\(foundryEffectDetails(effect))"
                }
                sections.append("**Effects**\n\n\(effects.joined(separator: "\n\n"))")
            }
            return RuleEntryModel(
                id: FoundryRuleIdentity.uuid(
                    for: "\(sourceIdentifier)#embedded#\(embedded.id)"
                ),
                name: FoundryTextDecoder.decodedText(embedded.name),
                content: sections.joined(separator: "\n\n"),
                kind: .embeddedRule
            )
        })

        result.append(contentsOf: rule.effects.enumerated().map { index, effect in
            return RuleEntryModel(
                id: FoundryRuleIdentity.uuid(
                    for: "\(sourceIdentifier)#effect#\(effect.id)"
                ),
                name: effect.name.isEmpty
                    ? "Effect \(index + 1)"
                    : FoundryTextDecoder.decodedText(effect.name),
                content: foundryEffectDetails(effect),
                kind: .effect
            )
        })
        return result
    }

    /// Imported text placed into rule markdown. Emphasis and code markers are escaped so a value
    /// cannot break the entry's structure, and `](` and `://` are split by a zero-width space so
    /// it cannot form a link, nor one of the app's own item links. Line breaks become spaces and a
    /// leading heading, quote, list or reference marker is escaped, so a value cannot start a new
    /// block of its own. See CODE_AUDIT_22 §6.5, CODE_AUDIT_23 §6.8.
    static func inert(_ text: String) -> String {
        var result = ""
        let singleLine = text
            .replacing("\r\n", with: " ")
            .replacing("\n", with: " ")
            .replacing("\r", with: " ")
        for character in singleLine {
            if "\\*_`".contains(character) { result.append("\\") }
            result.append(character)
        }
        if let first = result.first(where: { !$0.isWhitespace }), "#>-+[<".contains(first),
           let index = result.firstIndex(of: first) {
            result.insert("\\", at: index)
        }
        return result
            .replacing("](", with: "]\u{200B}(")
            .replacing("://", with: ":\u{200B}//")
    }

    /// `inert` for text with several lines: every line is neutralized on its own and the line
    /// and paragraph breaks stay, so a description keeps its paragraphs but cannot form a link,
    /// an item link or a block of its own. Values only go through `linkInert`, so a bonus like `+2`
    /// stays as it is. Names are not passed through it: they are shown as
    /// plain text, never as markdown, and escaping would print the backslashes. See
    /// CODE_AUDIT_26 §6.16.
    static func inertParagraphs(_ text: String) -> String {
        text
            .replacing("\r\n", with: "\n")
            .replacing("\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { inert(String($0)) }
            .joined(separator: "\n")
    }

    /// Values keep their text as it is, a leading `+` or `-` of a bonus included, and only lose
    /// what can turn them into a link: `](` and `://` are split by a zero-width space, so neither
    /// a web link nor one of the app's own item links can form. Line breaks stay. See
    /// CODE_AUDIT_26 §6.16.
    static func linkInert(_ text: String) -> String {
        text
            .replacing("](", with: "]\u{200B}(")
            .replacing("://", with: ":\u{200B}//")
    }

    static func foundryReferenceDetails(
        _ reference: FoundryRuleReference,
        index: Int
    ) -> String {
        let label = reference.label?.isEmpty == false
            ? FoundryTextDecoder.decodedText(reference.label ?? reference.target)
            : FoundryTextDecoder.decodedText(reference.target)
        var lines = [
            "**Reference \(index + 1): \(inert(label))**",
            "- **Target:** \(inert(reference.target))",
            "- **Type:** \(reference.kind.rawValue)",
            "- **Source:** \(inert(reference.sourcePath))",
            "- **Token:** \(inert(reference.rawToken))",
        ]
        if let packName = reference.packName, !packName.isEmpty {
            lines.append("- **Pack:** \(inert(FoundryTextDecoder.decodedText(packName)))")
        }
        if let documentId = reference.documentId, !documentId.isEmpty {
            lines.append("- **Document:** \(inert(documentId))")
        }
        return lines.joined(separator: "\n")
    }

    static func foundryEffectDetails(_ effect: FoundryRuleEffect) -> String {
        var lines = [
            "- **ID:** \(inert(effect.id))",
            "- **Disabled:** \(effect.isDisabled ? "yes" : "no")",
            "- **Transfers to actor:** \(effect.transfersToActor ? "yes" : "no")",
        ]
        if !effect.statuses.isEmpty {
            lines.append(
                "- **Statuses:** \(effect.statuses.map { inert(FoundryTextDecoder.decodedText($0)) }.joined(separator: ", "))"
            )
        }
        if let duration = effect.duration {
            lines.append("- **Duration:** \(inert(presentation(duration)))")
        }
        if !effect.changes.isEmpty {
            lines.append("**Changes**")
            lines.append(contentsOf: effect.changes.map { change in
                let priority = change.priority.map { ", priority \($0)" } ?? ""
                return "- **\(inert(change.path)):** \(inert(presentation(change.operand))) (mode \(change.mode)\(priority))"
            })
        }
        return lines.joined(separator: "\n")
    }

    static func hierarchicalValues(
        _ value: FoundryJSONValue,
        sourceIdentifier: String
    ) -> [RuleEntryModel] {
        hierarchicalValues(
            FoundryValueHierarchy.nodes(from: value),
            sourceIdentifier: sourceIdentifier
        )
    }

    static func hierarchicalValues(
        _ values: [FoundryRuleValue],
        sourceIdentifier: String
    ) -> [RuleEntryModel] {
        hierarchicalValues(
            FoundryValueHierarchy.nodes(from: values),
            sourceIdentifier: sourceIdentifier
        )
    }

    static func hierarchicalValues(
        _ nodes: [FoundryValueNode],
        sourceIdentifier: String
    ) -> [RuleEntryModel] {
        let maximumPresentedValues = 500
        let valueCount = nodes.reduce(0) { $0 + $1.valueCount }
        var remainingValues = maximumPresentedValues
        var result = projectedValueEntries(
            nodes,
            sourceIdentifier: sourceIdentifier,
            parentId: nil,
            remainingValues: &remainingValues
        )
        if valueCount > maximumPresentedValues {
            result.append(RuleEntryModel(
                id: FoundryRuleIdentity.uuid(for: "\(sourceIdentifier)#source#remaining-values"),
                name: "Additional source values",
                content: "\(valueCount - maximumPresentedValues) values remain available in the lossless source payload.",
                kind: .source
            ))
        }
        return result
    }

    static func projectedValueEntries(
        _ nodes: [FoundryValueNode],
        sourceIdentifier: String,
        parentId: UUID?,
        remainingValues: inout Int
    ) -> [RuleEntryModel] {
        var entries: [RuleEntryModel] = []
        for node in nodes {
            guard remainingValues > 0 else { break }
            let pathIdentity = valuePathIdentity(node.pathComponents)
            if node.children.isEmpty, let value = node.value {
                remainingValues -= 1
                entries.append(RuleEntryModel(
                    id: FoundryRuleIdentity.uuid(
                        for: "\(sourceIdentifier)#value#\(pathIdentity)"
                    ),
                    name: FoundryTextDecoder.decodedText(node.component),
                    content: linkInert(presentation(value)),
                    kind: .value,
                    parentId: parentId
                ))
                continue
            }

            let groupId = FoundryRuleIdentity.uuid(
                for: "\(sourceIdentifier)#value-group#\(pathIdentity)"
            )
            var descendants: [RuleEntryModel] = []
            if let value = node.value, remainingValues > 0 {
                remainingValues -= 1
                descendants.append(RuleEntryModel(
                    id: FoundryRuleIdentity.uuid(
                        for: "\(sourceIdentifier)#value#\(pathIdentity)#own"
                    ),
                    name: "value",
                    content: linkInert(presentation(value)),
                    kind: .value,
                    parentId: groupId
                ))
            }
            descendants.append(contentsOf: projectedValueEntries(
                node.children,
                sourceIdentifier: sourceIdentifier,
                parentId: groupId,
                remainingValues: &remainingValues
            ))
            guard !descendants.isEmpty else { continue }

            entries.append(RuleEntryModel(
                id: groupId,
                name: FoundryTextDecoder.decodedText(node.component),
                content: "",
                kind: .group,
                parentId: parentId
            ))
            entries.append(contentsOf: descendants)
        }
        return entries
    }

    static func projectedRuleValues(
        _ values: [FoundryRuleValue]
    ) -> [FoundryRuleValue] {
        let paths = values.map {
            $0.path.split(separator: ".", omittingEmptySubsequences: true).map(String.init)
        }
        let hasCommonTechnicalSystemRoot = !paths.isEmpty && paths.allSatisfy {
            $0.count > 1 && $0.first == "system"
        }
        guard hasCommonTechnicalSystemRoot else { return values }
        return zip(values, paths).map { value, path in
            FoundryRuleValue(
                path: path.dropFirst().joined(separator: "."),
                value: value.value
            )
        }
    }

    static func valuePathIdentity(_ components: [String]) -> String {
        guard !components.isEmpty else { return "root" }
        return components.map { component in
            "\(component.utf8.count):\(component)"
        }.joined()
    }

    static func presentation(_ value: FoundryJSONValue) -> String {
        switch value {
        case .string(let value): return FoundryTextDecoder.plainText(fromHTML: value)
        // Stored content must not depend on the importing device: no locale separators, no
        // grouping and the full precision of the number (`.number` rounds to 3 decimals).
        // See CODE_AUDIT_26 §5.130.
        case .integer(let value): return String(value)
        case .unsignedInteger(let value): return String(value)
        case .number(let value): return String(value)
        case .bool(let value): return value ? "true" : "false"
        case .null: return "null"
        case .array(let values): return values.map(presentation).joined(separator: ", ")
        case .object:
            guard let data = try? JSONCoding.encoder.encode(value),
                  let text = String(data: data, encoding: .utf8) else { return "" }
            return text
        }
    }

    static func readableText(fromHTML html: String?) -> String {
        FoundryTextDecoder.plainText(fromHTML: html)
    }

    static func orderedUnique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for value in values {
            let decoded = FoundryTextDecoder.decodedText(value)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !decoded.isEmpty,
                  seen.insert(decoded.localizedLowercase).inserted else { continue }
            result.append(decoded)
        }
        return result
    }
}
