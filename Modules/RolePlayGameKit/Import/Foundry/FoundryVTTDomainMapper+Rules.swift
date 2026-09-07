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

        let systemFolderID = stableID("rules#system#\(rulePackage.manifest.id)")
        addFolder(
            id: systemFolderID,
            module: .rule,
            name: rulePackage.manifest.title,
            parentID: nil,
            sourceID: "rules:system:\(rulePackage.manifest.id)"
        )

        for compendium in rulePackage.compendiums {
            try await cooperativeCheckpoint()
            let packName = compendium.manifest.name
            let packFolderID = stableID("rules#pack#\(packName)")
            addFolder(
                id: packFolderID,
                module: .rule,
                name: compendium.manifest.label,
                parentID: systemFolderID,
                sourceID: "rules:pack:\(packName)"
            )

            var foldersByID: [String: FoundryFolder] = [:]
            var projectedFolderIDs: [String: UUID] = [:]
            for folder in compendium.folders {
                try await cooperativeCheckpoint()
                guard foldersByID[folder.id] == nil else {
                    warnings.append("Rule compendium \(packName) contains duplicate folder id \(folder.id); the first folder was retained.")
                    continue
                }
                foldersByID[folder.id] = folder
                projectedFolderIDs[folder.id] = stableID(
                    "rules#pack#\(packName)#folder#\(folder.id)"
                )
            }

            for folder in compendium.folders where foldersByID[folder.id] == folder {
                try await cooperativeCheckpoint()
                guard let folderID = projectedFolderIDs[folder.id] else { continue }
                let parentID = safeRuleFolderParent(
                    for: folder,
                    foldersByID: foldersByID,
                    projectedFolderIDs: projectedFolderIDs,
                    fallback: packFolderID,
                    packName: packName
                )
                addFolder(
                    id: folderID,
                    module: .rule,
                    name: folder.name,
                    parentID: parentID,
                    sourceID: "rules:pack:\(packName):folder:\(folder.id)"
                )
            }

            for rule in compendium.rules {
                try await cooperativeCheckpoint()
                let parentID: UUID
                if let foundryFolderID = rule.folderID,
                   let projectedFolderID = projectedFolderIDs[foundryFolderID] {
                    parentID = projectedFolderID
                } else {
                    parentID = packFolderID
                    if let missingFolderID = rule.folderID, !missingFolderID.isEmpty {
                        warnings.append("Rule \(rule.name) references missing folder \(missingFolderID) in \(packName); it was placed at the compendium root.")
                    }
                }
                let scopedRuleID = stableID("rule#\(rule.id)")
                let identityNamespace = "external-source:\(sourceScopeID.uuidString.lowercased())#rule#\(rule.id)"
                let model = RuleModel.foundry(
                    rule,
                    manifest: rulePackage.manifest,
                    id: scopedRuleID,
                    identityNamespace: identityNamespace,
                    parentId: parentID
                )
                prepareRuleProjection(model, from: rule)
                add(model, module: .rule, sourceID: rule.id)
                recordRuleAliases(
                    rule,
                    systemID: rulePackage.manifest.id,
                    itemId: scopedRuleID
                )
            }
        }
    }

    func safeRuleFolderParent(
        for folder: FoundryFolder,
        foldersByID: [String: FoundryFolder],
        projectedFolderIDs: [String: UUID],
        fallback: UUID,
        packName: String
    ) -> UUID {
        guard let parentFoundryID = folder.parentID, !parentFoundryID.isEmpty else {
            return fallback
        }
        guard projectedFolderIDs[parentFoundryID] != nil else {
            warnings.append("Rule folder \(folder.name) references missing parent \(parentFoundryID) in \(packName); it was placed at the compendium root.")
            return fallback
        }

        var visited = Set([folder.id])
        var candidate: String? = parentFoundryID
        while let current = candidate {
            guard visited.insert(current).inserted else {
                warnings.append("Rule folder hierarchy in \(packName) contains a cycle at \(folder.name); it was placed at the compendium root.")
                return fallback
            }
            candidate = foldersByID[current]?.parentID
        }
        return projectedFolderIDs[parentFoundryID] ?? fallback
    }

    func recordRuleAliases(_ rule: FoundryRuleDefinition, systemID: String, itemId: UUID) {
        for alias in foundryRuleAliases(rule, systemID: systemID) {
            recordMapping(sourceID: alias, module: .rule, itemId: itemId)
        }
    }

    /// Foundry has used both `system.pack.id` compendium references and fully-qualified UUIDs
    /// containing the document type. Keep the aliases already emitted by earlier imports while
    /// also recognizing both canonical link shapes.
    func foundryRuleAliases(_ rule: FoundryRuleDefinition, systemID: String) -> Set<String> {
        let identifiers = Set([
            rule.id,
            rule.documentID,
            "\(rule.packName).\(rule.documentID)",
            "\(systemID).\(rule.packName).\(rule.documentID)",
            "Compendium.\(systemID).\(rule.id)",
            "Compendium.\(systemID).\(rule.packName).\(rule.documentID)",
            "Compendium.\(systemID).\(rule.packName).\(rule.documentType).\(rule.documentID)",
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
                    updated.name = sanitizedFoundryText(
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
                    updated.name = sanitizedFoundryText(embeddedRule.name)
                    updated.content = projectedEmbeddedRuleContent(embeddedRule)
                } else {
                    updated.content = safeText(entry.content)
                }
                embeddedRuleIndex += 1
            case .effect:
                if rule.effects.indices.contains(effectIndex) {
                    let effect = rule.effects[effectIndex]
                    let fallbackName = "Effect \(effectIndex + 1)"
                    updated.name = sanitizedFoundryText(
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
        let sanitizedToken = sanitizedFoundryText(reference.rawToken)
        let rewrittenToken = rewriteFoundryLinks(sanitizedToken)
        let target: String
        if rewrittenToken != sanitizedToken {
            target = rewrittenToken
        } else if let destination = destination(for: reference) {
            let label = sanitizedFoundryText(
                reference.label?.isEmpty == false ? reference.label : reference.target
            )
            target = markdownLink(
                name: label,
                module: destination.module,
                itemId: destination.itemId
            )
        } else {
            target = sanitizedFoundryText(reference.target)
        }

        var details = "**Target:** \(target)"
        if let packName = reference.packName, !packName.isEmpty {
            details += "\n\n**Pack:** \(sanitizedFoundryText(packName))"
        }
        if let documentID = reference.documentID, !documentID.isEmpty {
            details += "\n\n**Document:** \(sanitizedFoundryText(documentID))"
        }
        details += "\n\n**Type:** \(sanitizedFoundryText(reference.kind.rawValue))"
        if !reference.sourcePath.isEmpty {
            details += "\n\n**Source:** \(sanitizedFoundryText(reference.sourcePath))"
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
            let path = sanitizedFoundryText(value.path)
            let presentation = presentedFoundryValue(value.value)
            return "- **\(path):** \(presentation)"
        }
        if !values.isEmpty {
            sections.append("**Values**\n\(values.joined(separator: "\n"))")
        }
        if !rule.references.isEmpty {
            let references = rule.references.enumerated().map { index, reference in
                let label = sanitizedFoundryText(
                    reference.label?.isEmpty == false ? reference.label : reference.target
                )
                return "**Reference \(index + 1): \(label)**\n\(projectedRuleReferenceContent(reference))"
            }
            sections.append("**References**\n\n\(references.joined(separator: "\n\n"))")
        }
        if !rule.effects.isEmpty {
            let effects = rule.effects.enumerated().map { index, effect in
                let fallbackName = "Effect \(index + 1)"
                let name = sanitizedFoundryText(
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
            "- **ID:** \(sanitizedFoundryText(effect.id))",
            "- **Disabled:** \(effect.isDisabled ? "yes" : "no")",
            "- **Transfers to actor:** \(effect.transfersToActor ? "yes" : "no")",
        ]
        if !effect.statuses.isEmpty {
            let statuses = effect.statuses.map { sanitizedFoundryText($0) }.joined(separator: ", ")
            lines.append("- **Statuses:** \(statuses)")
        }
        if let duration = effect.duration {
            lines.append("- **Duration:** \(presentedFoundryValue(duration))")
        }
        if !effect.changes.isEmpty {
            lines.append("**Changes**")
            lines.append(contentsOf: effect.changes.map { change in
                let path = sanitizedFoundryText(change.path)
                let operand = presentedFoundryValue(change.operand)
                let priority = change.priority.map { ", priority \($0)" } ?? ""
                return "- **\(path):** \(operand) (mode \(change.mode)\(priority))"
            })
        }
        return lines.joined(separator: "\n")
    }
}
