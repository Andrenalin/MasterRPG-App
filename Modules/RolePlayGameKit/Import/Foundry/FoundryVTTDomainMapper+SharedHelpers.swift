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

// MARK: - Shared conversion helpers

extension FoundryMappingState {
    struct DestinationKey: Hashable {
        let module: NetworkModules
        let id: UUID
    }

    struct FolderKey: Hashable {
        let module: NetworkModules
        let documentType: FoundryDocumentType
        let scope: String
        let foundryID: String
    }

    struct FolderAliasKey: Hashable {
        let module: NetworkModules
        let documentType: FoundryDocumentType
        let foundryID: String
    }

    struct FolderDeclaration {
        let id: String
        let documentID: String
        let name: String
        let parentID: String?
        let documentType: FoundryDocumentType
        let scope: String
    }

    struct ResourceKey: Hashable {
        let module: NetworkModules
        let path: String
    }

    struct Destination: Hashable {
        let module: NetworkModules
        let itemId: UUID
    }

    func add<Model>(
        _ model: Model,
        module: NetworkModules,
        sourceID: String,
        attachment: ExternalImportAttachment? = nil,
        decisionOwnerID: UUID? = nil,
        warnings: [String] = []
    ) where Model: ItemDataAccessible & Observable {
        var model = model
        model.name = sanitizedFoundryText(model.name)
        let key = DestinationKey(module: module, id: model.id)
        recordMapping(sourceID: sourceID, module: module, itemId: model.id)
        guard emittedItems.insert(key).inserted else { return }
        items.append(ExternalImportBatchItem(
            id: model.id,
            module: module,
            name: model.name,
            model: model,
            provenance: ExternalImportProvenance(
                source: provenance.source,
                sourceScopeID: provenance.sourceScopeID,
                packageIdentifier: packageIdentifier,
                documentIdentifier: sourceID,
                sourcePath: sourceURL.lastPathComponent,
                sourceVersion: provenance.sourceVersion
            ),
            attachment: attachment,
            decisionOwnerID: decisionOwnerID,
            warnings: warnings
        ))
    }

    func recordMapping(sourceID: String, module: NetworkModules, itemId: UUID, entryID: UUID? = nil) {
        mappingReferences[sourceID, default: []].insert(
            FoundryImportMappingReference(module: module, itemId: itemId, entryID: entryID)
        )
    }

    func stableID(_ component: String) -> UUID {
        FoundryRuleIdentity.uuid(for: "external-source:\(sourceScopeID.uuidString.lowercased())#\(component)")
    }

    func mappingOrder(_ lhs: FoundryImportMappingReference, _ rhs: FoundryImportMappingReference) -> Bool {
        if lhs.module.rawValue != rhs.module.rawValue { return lhs.module.rawValue < rhs.module.rawValue }
        if lhs.itemId != rhs.itemId { return lhs.itemId.uuidString < rhs.itemId.uuidString }
        return (lhs.entryID?.uuidString ?? "") < (rhs.entryID?.uuidString ?? "")
    }

    func folderID(for document: FoundryDocument, module: NetworkModules) -> UUID? {
        document.folderID.flatMap {
            resolveFolder(
                module: module,
                documentType: document.documentType,
                scope: canonicalScope(of: document.id, fallback: document.parentID ?? packageIdentifier),
                foundryID: $0
            )
        }
    }

    func modules(for type: FoundryDocumentType) -> [NetworkModules] {
        if type == .item {
            var result: [NetworkModules] = []
            if selectedCategories.contains(.items) {
                result.append(.value)
            }
            if selectedCategories.contains(.rules), package.rulePackage == nil {
                result.append(.rule)
            }
            return result
        }
        let mapping: (FoundryImportCategory, [NetworkModules])? = switch type {
        case .actor: (.actors, [.value])
        case .scene, .level: (.scenes, [.map])
        case .journalEntry: (.journals, [.adventure])
        case .adventure: (.adventures, [.adventure])
        case .combat: (.combats, [.adventure])
        case .chatMessage: (.chat, [.adventure])
        case .macro: (.macros, [.adventure])
        case .rollTable: (.tables, [.table])
        case .playlist: (.playlists, [.audio])
        case .cards: (.cards, [.table])
        default: nil
        }
        guard let mapping, selectedCategories.contains(mapping.0) else { return [] }
        return mapping.1
    }

    func predictedDestination(for document: FoundryDocument) -> Destination? {
        switch document.documentType {
        case .actor where selectedCategories.contains(.actors):
            Destination(module: .value, itemId: stableID("\(document.id)#character"))
        case .item:
            if let parentID = document.parentID, documentTypesByID[parentID] == .actor {
                selectedCategories.contains(.actors)
                    ? Destination(module: .value, itemId: stableID("\(document.id)#character-item"))
                    : nil
            } else if selectedCategories.contains(.rules), package.rulePackage == nil {
                Destination(module: .rule, itemId: stableID("\(document.id)#rule"))
            } else {
                selectedCategories.contains(.items)
                    ? Destination(module: .value, itemId: stableID("\(document.id)#item"))
                    : nil
            }
        case .scene where selectedCategories.contains(.scenes):
            Destination(module: .map, itemId: stableID("\(document.id)#map"))
        case .level where selectedCategories.contains(.scenes): Destination(
            module: .map,
            itemId: levelMapIDs[document.id] ?? stableID("\(document.id)#level-map")
        )
        case .journalEntry where selectedCategories.contains(.journals):
            Destination(module: .adventure, itemId: stableID("\(document.id)#journal"))
        case .journalEntryPage where selectedCategories.contains(.journals):
            document.parentID.map { Destination(module: .adventure, itemId: stableID("\($0)#journal")) }
        case .rollTable where selectedCategories.contains(.tables):
            Destination(module: .table, itemId: stableID("\(document.id)#table"))
        case .tableResult where selectedCategories.contains(.tables):
            document.parentID.map { Destination(module: .table, itemId: stableID("\($0)#table")) }
        case .playlist where selectedCategories.contains(.playlists):
            Destination(module: .audio, itemId: stableID("\(document.id)#playlist"))
        case .playlistSound where selectedCategories.contains(.playlists):
            document.parentID.map { Destination(module: .audio, itemId: stableID("\($0)#playlist")) }
        case .cards where selectedCategories.contains(.cards):
            Destination(module: .table, itemId: stableID("\(document.id)#cards"))
        case .card where selectedCategories.contains(.cards):
            document.parentID.map { Destination(module: .table, itemId: stableID("\($0)#cards")) }
        case .adventure where selectedCategories.contains(.adventures):
            Destination(module: .adventure, itemId: stableID("\(document.id)#adventure"))
        case .combat where selectedCategories.contains(.combats):
            Destination(module: .adventure, itemId: stableID("\(document.id)#combat"))
        case .combatant where selectedCategories.contains(.combats):
            document.parentID.map { Destination(module: .adventure, itemId: stableID("\($0)#combat")) }
        case .macro where selectedCategories.contains(.macros):
            Destination(module: .adventure, itemId: stableID("\(document.id)#macro"))
        default: nil
        }
    }

    func module(for path: String) -> NetworkModules? {
        if let plan = FoundryMediaNormalizer.plan(for: path) {
            return switch plan.kind {
            case .image: .photo
            case .audio: .audio
            }
        }
        return switch URL(filePath: canonicalResourcePath(path)).pathExtension.lowercased() {
        case "pdf": .pdf
        case "usdz": .space
        default: nil
        }
    }

    /// Canonical lookup keeps path case intact. Foundry packages can be authored on a
    /// case-sensitive file system, so a case-folded path is only safe as a secondary alias.
    func canonicalResourcePath(_ path: String) -> String {
        let decoded = path.removingPercentEncoding ?? path
        let noQuery = decoded.split(separator: "?", maxSplits: 1).first.map(String.init) ?? decoded
        return noQuery.split(separator: "#", maxSplits: 1).first
            .map(String.init)?
            .replacing("\\", with: "/")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            ?? ""
    }

    func resourceAlias(_ path: String) -> String {
        canonicalResourcePath(path).lowercased()
    }

    func actorCategory(_ subtype: String?) -> ItemListCategory {
        guard let subtype = subtype?.lowercased() else { return .monster }
        if subtype == "character" || subtype == "pc" || subtype.contains("player") { return .character }
        if subtype.contains("game") && subtype.contains("master") { return .gameMaster }
        return .monster
    }

    func tableCategory(_ document: FoundryDocument) -> ItemListCategory {
        let text = "\(document.name) \(document.subtype ?? "")".lowercased()
        return text.contains("loot") ? .loot : .generator
    }

    func foundryTags(_ document: FoundryDocument) -> [String] {
        ["Foundry VTT", document.subtype].compactMap { value in
            guard let value, !value.isEmpty else { return nil }
            return FoundryTextDecoder.decodedText(value)
        }
    }

    func number(_ value: FoundryJSONValue?) -> Double? {
        switch value {
        case .integer(let value): Double(value)
        case .unsignedInteger(let value): Double(value)
        case .number(let value): value
        default: nil
        }
    }

    func firstValue(_ value: FoundryJSONValue, paths: [String]) -> FoundryJSONValue? {
        paths.lazy.compactMap { value.value(at: $0) }.first
    }

    func firstString(_ value: FoundryJSONValue, paths: [String]) -> String? {
        paths.lazy.compactMap { value.value(at: $0)?.stringValue }.first
    }

    func sanitizedFoundryText(_ optionalHTML: String?) -> String {
        FoundryTextDecoder.plainText(fromHTML: optionalHTML)
    }

    func safeText(_ optionalHTML: String?) -> String {
        rewriteFoundryLinks(sanitizedFoundryText(optionalHTML))
    }

    func decodedFoundryText(_ text: String?) -> String {
        guard let text else { return "" }
        return rewriteFoundryLinks(
            FoundryTextDecoder.decodedText(text)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    func prepareGenericRuleProjection(_ model: RuleModel, descriptionHTML: String?) {
        model.description = safeText(descriptionHTML)
        model.entries = model.entries.map { entry in
            var updated = entry
            updated.content = entry.kind == .value
                ? decodedFoundryText(entry.content)
                : safeText(entry.content)
            return updated
        }
    }

    func rewriteFoundryLinks(_ input: String) -> String {
        let linkTypes = [
            "UUID", "Actor", "Item", "Scene", "JournalEntry", "JournalEntryPage",
            "RollTable", "TableResult", "Playlist", "PlaylistSound", "Cards", "Card",
            "Adventure", "Combat", "Macro", "Compendium",
        ].joined(separator: "|")
        guard let expression = try? NSRegularExpression(
            pattern: #"@("# + linkTypes + #")\[([^\]\r\n]+)\](?:\{([^}\r\n]+)\})?"#
        ) else {
            return input
        }
        var output = input
        let matches = expression.matches(in: input, range: NSRange(input.startIndex..<input.endIndex, in: input))
        for match in matches.reversed() {
            guard let totalRange = Range(match.range(at: 0), in: output),
                  let typeRange = Range(match.range(at: 1), in: output),
                  let identifierRange = Range(match.range(at: 2), in: output) else { continue }
            let type = String(output[typeRange])
            let identifier = String(output[identifierRange])
            let candidates: [String] = switch type {
            case "UUID": [identifier]
            case "Compendium": [identifier, "Compendium.\(identifier)"]
            default: ["\(type).\(identifier)", identifier]
            }
            guard let destination = candidates.lazy.compactMap({ self.targetsByFoundryUUID[$0] }).first else { continue }
            let label: String
            if match.range(at: 3).location != NSNotFound, let labelRange = Range(match.range(at: 3), in: output) {
                label = String(output[labelRange])
            } else {
                label = identifier
            }
            output.replaceSubrange(totalRange, with: markdownLink(
                name: label,
                module: destination.module,
                itemId: destination.itemId
            ))
        }
        return output
    }

    func foundryReferenceAliases(for identifier: String) -> Set<String> {
        var aliases = Set([identifier])
        let components = identifier.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        if components.first == "Compendium", components.count >= 5 {
            // Legacy @Compendium links omit both the Compendium prefix and document type.
            aliases.insert([components[1], components[2], components.last ?? ""].joined(separator: "."))
        }
        return aliases
    }

    func markdownLink(name: String, module: NetworkModules, itemId: UUID) -> String {
        let escapedName = name
            .replacing("\\", with: "\\\\")
            .replacing("[", with: "\\[")
            .replacing("]", with: "\\]")
            .replacing("\n", with: " ")
            .replacing("\r", with: " ")
        return LinkBuilder.markdown(name: escapedName, module: module, itemId: itemId)
    }

    func inertCodeBlock(_ source: String) -> String {
        let longestBacktickRun = source.split(separator: "`", omittingEmptySubsequences: false)
            .dropLast()
            .reduce(0) { longest, _ in max(longest, 1) }
        // Four backticks safely contain normal triple-backtick source. If a future macro contains
        // a longer fence, extend the delimiter until it cannot terminate the block.
        var fenceLength = max(4, longestBacktickRun + 1)
        while source.contains(String(repeating: "`", count: fenceLength)) {
            fenceLength += 1
        }
        let fence = String(repeating: "`", count: fenceLength)
        return "\(fence)text\n\(source)\n\(fence)"
    }

    func displayString(_ value: FoundryJSONValue) -> String {
        switch value {
        case .object(let values):
            values.keys.sorted().compactMap { key in values[key].map { "\(key): \(displayString($0))" } }.joined(separator: ", ")
        case .array(let values): values.map(displayString).joined(separator: ", ")
        case .string(let value): value
        case .integer(let value): String(value)
        case .unsignedInteger(let value): String(value)
        case .number(let value): String(value)
        case .bool(let value): value ? "true" : "false"
        case .null: "null"
        }
    }

    func presentedFoundryValue(_ value: FoundryJSONValue) -> String {
        switch value {
        case .object(let values):
            values.keys.sorted().compactMap { key in
                values[key].map {
                    "\(sanitizedFoundryText(key)): \(presentedFoundryValue($0))"
                }
            }.joined(separator: ", ")
        case .array(let values):
            values.map(presentedFoundryValue).joined(separator: ", ")
        case .string(let value):
            safeText(value)
        case .integer, .unsignedInteger, .number, .bool, .null:
            decodedFoundryText(displayString(value))
        }
    }

    func combatantSummary(_ combatant: FoundryDocument) -> String {
        let initiative = number(combatant.rawData["initiative"])
        let defeated = combatant.rawData["defeated"]?.boolValue ?? false
        let hidden = combatant.rawData["hidden"]?.boolValue ?? false
        return [
            initiative.map { "Initiative: \($0.formatted())" },
            "Defeated: \(defeated ? "yes" : "no")",
            "Hidden: \(hidden ? "yes" : "no")"
        ].compactMap { $0 }.joined(separator: "\n")
    }

    func simpleModifier(_ formula: String) -> Double {
        let withoutDice = formula.replacing(/([0-9]*)[dD]([0-9]+)/, with: "")
        guard let expression = try? NSRegularExpression(pattern: #"[+-]\s*[0-9]+(?:\.[0-9]+)?"#) else {
            return 0
        }
        let matches = expression.matches(
            in: withoutDice,
            range: NSRange(withoutDice.startIndex..<withoutDice.endIndex, in: withoutDice)
        )
        return matches.compactMap { match in
            Range(match.range, in: withoutDice).flatMap {
                Double(withoutDice[$0].replacing(" ", with: ""))
            }
        }.reduce(0, +)
    }

    func base64Hash(_ hexadecimal: String) -> String? {
        guard hexadecimal.count.isMultiple(of: 2) else { return nil }
        var data = Data()
        var index = hexadecimal.startIndex
        while index < hexadecimal.endIndex {
            let end = hexadecimal.index(index, offsetBy: 2)
            guard let byte = UInt8(hexadecimal[index..<end], radix: 16) else { return nil }
            data.append(byte)
            index = end
        }
        return data.base64EncodedString()
    }
}
