// @copyright André Trettin

import AdventureRPG
import AudioRPG
import CharacterRPG
import CoreRPG
import DiceRPG
import Foundation
import MapRPG
import Observation
import PdfRPG
import PhotoRPG
import RuleRPG
import SpaceRPG
import SwiftUI
import TableRPG
import UniformTypeIdentifiers

// MARK: - Rules

extension FoundryMappingState {
    /// Projects a normalized Foundry system package into an editable RuleRPG hierarchy while the
    /// complete normalized package continues to live in the source archive.
    func createRuleProjection() async throws {
        guard let rulePackage = privacyFilteredPackage.rulePackage else { return }

        let systemFolderId = stableId("rules#system#\(rulePackage.manifest.id)")
        addFolder(
            id: systemFolderId,
            module: .rule,
            name: rulePackage.manifest.title,
            parentId: nil,
            sourceId: "rules:system:\(rulePackage.manifest.id)"
        )

        for compendium in rulePackage.compendiums {
            try await cooperativeCheckpoint()
            let packName = compendium.manifest.name
            let packFolderId = stableId("rules#pack#\(packName)")
            addFolder(
                id: packFolderId,
                module: .rule,
                name: compendium.manifest.label,
                parentId: systemFolderId,
                sourceId: "rules:pack:\(packName)"
            )

            var foldersById: [String: FoundryFolder] = [:]
            var projectedFolderIds: [String: UUID] = [:]
            for folder in compendium.folders {
                try await cooperativeCheckpoint()
                guard foldersById[folder.id] == nil else {
                    warnings.append(String(localized: "Rule compendium \(packName) contains duplicate folder id \(folder.id); the first folder was retained.", bundle: .module))
                    continue
                }
                foldersById[folder.id] = folder
                projectedFolderIds[folder.id] = stableId(
                    "rules#pack#\(packName)#folder#\(folder.id)"
                )
            }

            for folder in compendium.folders where foldersById[folder.id] == folder {
                try await cooperativeCheckpoint()
                guard let folderId = projectedFolderIds[folder.id] else { continue }
                let parentId = safeRuleFolderParent(
                    for: folder,
                    foldersById: foldersById,
                    projectedFolderIds: projectedFolderIds,
                    fallback: packFolderId,
                    packName: packName
                )
                addFolder(
                    id: folderId,
                    module: .rule,
                    name: folder.name,
                    parentId: parentId,
                    sourceId: "rules:pack:\(packName):folder:\(folder.id)"
                )
            }

            for rule in compendium.rules {
                try await cooperativeCheckpoint()
                let parentId: UUID
                if let foundryFolderId = rule.folderId,
                   let projectedFolderId = projectedFolderIds[foundryFolderId] {
                    parentId = projectedFolderId
                } else {
                    parentId = packFolderId
                    if let missingFolderId = rule.folderId, !missingFolderId.isEmpty {
                        warnings.append(String(localized: "Rule \(rule.name) references missing folder \(missingFolderId) in \(packName); it was placed at the compendium root.", bundle: .module))
                    }
                }
                let scopedRuleId = stableId("rule#\(rule.id)")
                let identityNamespace = "external-source:\(sourceScopeId.uuidString.lowercased())#rule#\(rule.id)"
                let model = RuleModel.foundry(
                    rule,
                    manifest: rulePackage.manifest,
                    id: scopedRuleId,
                    identityNamespace: identityNamespace,
                    parentId: parentId
                )
                prepareRuleProjection(model, from: rule)
                add(model, module: .rule, sourceId: rule.id)
                recordRuleAliases(
                    rule,
                    systemId: rulePackage.manifest.id,
                    itemId: scopedRuleId
                )
            }
        }
    }

    func safeRuleFolderParent(
        for folder: FoundryFolder,
        foldersById: [String: FoundryFolder],
        projectedFolderIds: [String: UUID],
        fallback: UUID,
        packName: String
    ) -> UUID {
        guard let parentFoundryId = folder.parentId, !parentFoundryId.isEmpty else {
            return fallback
        }
        guard projectedFolderIds[parentFoundryId] != nil else {
            warnings.append(String(localized: "Rule folder \(folder.name) references missing parent \(parentFoundryId) in \(packName); it was placed at the compendium root.", bundle: .module))
            return fallback
        }

        var visited = Set([folder.id])
        var candidate: String? = parentFoundryId
        while let current = candidate {
            guard visited.insert(current).inserted else {
                warnings.append(String(localized: "Rule folder hierarchy in \(packName) contains a cycle at \(folder.name); it was placed at the compendium root.", bundle: .module))
                return fallback
            }
            candidate = foldersById[current]?.parentId
        }
        return projectedFolderIds[parentFoundryId] ?? fallback
    }

    func recordRuleAliases(_ rule: FoundryRuleDefinition, systemId: String, itemId: UUID) {
        for alias in foundryRuleAliases(rule, systemId: systemId) {
            recordMapping(sourceId: alias, module: .rule, itemId: itemId)
        }
    }

    /// Foundry has used both `system.pack.id` compendium references and fully-qualified UUIDs
    /// containing the document type. Keep the aliases already emitted by earlier imports while
    /// also recognizing both canonical link shapes.
    func foundryRuleAliases(_ rule: FoundryRuleDefinition, systemId: String) -> Set<String> {
        let identifiers = Set([
            rule.id,
            rule.documentId,
            "\(rule.packName).\(rule.documentId)",
            "\(systemId).\(rule.packName).\(rule.documentId)",
            "Compendium.\(systemId).\(rule.id)",
            "Compendium.\(systemId).\(rule.packName).\(rule.documentId)",
            "Compendium.\(systemId).\(rule.packName).\(rule.documentType).\(rule.documentId)",
        ])
        return identifiers.reduce(into: Set<String>()) { aliases, identifier in
            aliases.formUnion(foundryReferenceAliases(for: identifier))
        }
    }

    /// The RuleRPG factories deliberately know nothing about mapper-local destinations. Apply the
    /// same text boundary used by every other projection only after all Foundry aliases are indexed.
    /// The normalized source payload is intentionally left untouched here.
    func prepareRuleProjection(_ model: RuleModel, from rule: FoundryRuleDefinition) {
        model.description = safeText(rule.descriptionHTML)

        var referenceIndex = 0
        var embeddedRuleIndex = 0
        var effectIndex = 0
        model.entries = model.entries.map { entry in
            var updated = entry
            switch entry.kind {
            case .reference:
                if rule.references.indices.contains(referenceIndex) {
                    let reference = rule.references[referenceIndex]
                    updated.name = inertText(
                        reference.label?.isEmpty == false ? reference.label : reference.target
                    )
                    updated.content = projectedRuleReferenceContent(reference)
                } else {
                    updated.content = safeText(entry.content)
                }
                referenceIndex += 1
            case .embeddedRule:
                if rule.embeddedRules.indices.contains(embeddedRuleIndex) {
                    let embeddedRule = rule.embeddedRules[embeddedRuleIndex]
                    updated.name = inertText(embeddedRule.name)
                    updated.content = projectedEmbeddedRuleContent(embeddedRule)
                } else {
                    updated.content = safeText(entry.content)
                }
                embeddedRuleIndex += 1
            case .effect:
                if rule.effects.indices.contains(effectIndex) {
                    let effect = rule.effects[effectIndex]
                    let fallbackName = "Effect \(effectIndex + 1)"
                    updated.name = inertText(
                        effect.name.isEmpty ? fallbackName : effect.name
                    )
                    updated.content = projectedRuleEffectContent(effect)
                } else {
                    updated.content = safeText(entry.content)
                }
                effectIndex += 1
            case .value:
                updated.content = decodedFoundryText(entry.content)
            default:
                updated.content = safeText(entry.content)
            }
            return updated
        }
    }

    func projectedRuleReferenceContent(_ reference: FoundryRuleReference) -> String {
        // Neutralised before the Foundry links are rewritten, so only the mapper's own links stay
        // live. See CODE_AUDIT_29 §6.1.
        let sanitizedToken = inertText(reference.rawToken)
        let rewrittenToken = rewriteFoundryLinks(sanitizedToken)
        let target: String
        if rewrittenToken != sanitizedToken {
            target = rewrittenToken
        } else if let destination = destination(for: reference) {
            let label = inertText(
                reference.label?.isEmpty == false ? reference.label : reference.target
            )
            target = markdownLink(
                name: label,
                module: destination.module,
                itemId: destination.itemId
            )
        } else {
            target = inertText(reference.target)
        }

        var details = "**Target:** \(target)"
        if let packName = reference.packName, !packName.isEmpty {
            details += "\n\n**Pack:** \(inertText(packName))"
        }
        if let documentId = reference.documentId, !documentId.isEmpty {
            details += "\n\n**Document:** \(inertText(documentId))"
        }
        details += "\n\n**Type:** \(inertText(reference.kind.rawValue))"
        if !reference.sourcePath.isEmpty {
            details += "\n\n**Source:** \(inertText(reference.sourcePath))"
        }
        return details
    }

    func destination(for reference: FoundryRuleReference) -> Destination? {
        var identifiers = [reference.target]
        if reference.kind == .compendium, !reference.target.hasPrefix("Compendium.") {
            identifiers.append("Compendium.\(reference.target)")
        }
        for identifier in identifiers {
            if let destination = targetsByFoundryUUID[identifier] {
                return destination
            }
            for alias in foundryReferenceAliases(for: identifier) {
                if let destination = targetsByFoundryUUID[alias] {
                    return destination
                }
            }
        }
        return nil
    }

    func projectedEmbeddedRuleContent(_ rule: FoundryEmbeddedRule) -> String {
        var sections = [safeText(rule.descriptionHTML)].filter { !$0.isEmpty }
        let values = rule.values.map { value in
            let path = inertText(value.path)
            let presentation = presentedFoundryValue(value.value)
            return "- **\(path):** \(presentation)"
        }
        if !values.isEmpty {
            sections.append("**Values**\n\(values.joined(separator: "\n"))")
        }
        if !rule.references.isEmpty {
            let references = rule.references.enumerated().map { index, reference in
                let label = inertText(
                    reference.label?.isEmpty == false ? reference.label : reference.target
                )
                return "**Reference \(index + 1): \(label)**\n\(projectedRuleReferenceContent(reference))"
            }
            sections.append("**References**\n\n\(references.joined(separator: "\n\n"))")
        }
        if !rule.effects.isEmpty {
            let effects = rule.effects.enumerated().map { index, effect in
                let fallbackName = "Effect \(index + 1)"
                let name = inertText(
                    effect.name.isEmpty ? fallbackName : effect.name
                )
                return "**\(name)**\n\(projectedRuleEffectContent(effect))"
            }
            sections.append("**Effects**\n\n\(effects.joined(separator: "\n\n"))")
        }
        return sections.joined(separator: "\n\n")
    }

    func projectedRuleEffectContent(_ effect: FoundryRuleEffect) -> String {
        var lines = [
            "- **ID:** \(inertText(effect.id))",
            "- **Disabled:** \(effect.isDisabled ? "yes" : "no")",
            "- **Transfers to actor:** \(effect.transfersToActor ? "yes" : "no")",
        ]
        if !effect.statuses.isEmpty {
            let statuses = effect.statuses.map { inertText($0) }.joined(separator: ", ")
            lines.append("- **Statuses:** \(statuses)")
        }
        if let duration = effect.duration {
            lines.append("- **Duration:** \(presentedFoundryValue(duration))")
        }
        if !effect.changes.isEmpty {
            lines.append("**Changes**")
            lines.append(contentsOf: effect.changes.map { change in
                let path = inertText(change.path)
                let operand = presentedFoundryValue(change.operand)
                let priority = change.priority.map { ", priority \($0)" } ?? ""
                return "- **\(path):** \(operand) (mode \(change.mode)\(priority))"
            })
        }
        return lines.joined(separator: "\n")
    }
}
