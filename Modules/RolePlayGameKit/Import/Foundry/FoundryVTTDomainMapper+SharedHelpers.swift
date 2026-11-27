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
        let foundryId: String
    }

    struct FolderAliasKey: Hashable {
        let module: NetworkModules
        let documentType: FoundryDocumentType
        let foundryId: String
    }

    struct FolderDeclaration {
        let id: String
        let documentId: String
        let name: String
        let parentId: String?
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
        sourceId: String,
        attachment: ExternalImportAttachment? = nil,
        decisionOwnerId: UUID? = nil,
        warnings: [String] = []
    ) where Model: ItemDataAccessible & Observable {
        var model = model
        model.name = sanitizedFoundryText(model.name)
        let key = DestinationKey(module: module, id: model.id)
        recordMapping(sourceId: sourceId, module: module, itemId: model.id)
        guard emittedItems.insert(key).inserted else { return }
        items.append(ExternalImportBatchItem(
            id: model.id,
            module: module,
            name: model.name,
            model: model,
            provenance: ExternalImportProvenance(
                source: provenance.source,
                sourceScopeId: provenance.sourceScopeId,
                packageIdentifier: packageIdentifier,
                documentIdentifier: sourceId,
                sourcePath: sourceUrl.lastPathComponent,
                sourceVersion: provenance.sourceVersion
            ),
            attachment: attachment,
            decisionOwnerId: decisionOwnerId,
            warnings: warnings
        ))
    }

    func recordMapping(sourceId: String, module: NetworkModules, itemId: UUID, entryId: UUID? = nil) {
        mappingReferences[sourceId, default: []].insert(
            FoundryImportMappingReference(module: module, itemId: itemId, entryId: entryId)
        )
    }

    func stableId(_ component: String) -> UUID {
        FoundryRuleIdentity.uuid(for: "external-source:\(sourceScopeId.uuidString.lowercased())#\(component)")
    }

    func mappingOrder(_ lhs: FoundryImportMappingReference, _ rhs: FoundryImportMappingReference) -> Bool {
        if lhs.module.rawValue != rhs.module.rawValue { return lhs.module.rawValue < rhs.module.rawValue }
        if lhs.itemId != rhs.itemId { return lhs.itemId.uuidString < rhs.itemId.uuidString }
        return (lhs.entryId?.uuidString ?? "") < (rhs.entryId?.uuidString ?? "")
    }

    func folderId(for document: FoundryDocument, module: NetworkModules) -> UUID? {
        document.folderId.flatMap {
            resolveFolder(
                module: module,
                documentType: document.documentType,
                scope: canonicalScope(of: document.id, fallback: document.parentId ?? packageIdentifier),
                foundryId: $0
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
            Destination(module: .value, itemId: stableId("\(document.id)#character"))
        case .item:
            if let parentId = document.parentId, documentTypesById[parentId] == .actor {
                selectedCategories.contains(.actors)
                    ? Destination(module: .value, itemId: stableId("\(document.id)#character-item"))
                    : nil
            } else if selectedCategories.contains(.rules), package.rulePackage == nil {
                Destination(module: .rule, itemId: stableId("\(document.id)#rule"))
            } else {
                selectedCategories.contains(.items)
                    ? Destination(module: .value, itemId: stableId("\(document.id)#item"))
                    : nil
            }
        case .scene where selectedCategories.contains(.scenes):
            Destination(module: .map, itemId: stableId("\(document.id)#map"))
        case .level where selectedCategories.contains(.scenes): Destination(
            module: .map,
            itemId: levelMapIds[document.id] ?? stableId("\(document.id)#level-map")
        )
        case .journalEntry where selectedCategories.contains(.journals):
            Destination(module: .adventure, itemId: stableId("\(document.id)#journal"))
        case .journalEntryPage where selectedCategories.contains(.journals):
            document.parentId.map { Destination(module: .adventure, itemId: stableId("\($0)#journal")) }
        case .rollTable where selectedCategories.contains(.tables):
            Destination(module: .table, itemId: stableId("\(document.id)#table"))
        case .tableResult where selectedCategories.contains(.tables):
            document.parentId.map { Destination(module: .table, itemId: stableId("\($0)#table")) }
        case .playlist where selectedCategories.contains(.playlists):
            Destination(module: .audio, itemId: stableId("\(document.id)#playlist"))
        case .playlistSound where selectedCategories.contains(.playlists):
            document.parentId.map { Destination(module: .audio, itemId: stableId("\($0)#playlist")) }
        case .cards where selectedCategories.contains(.cards):
            Destination(module: .table, itemId: stableId("\(document.id)#cards"))
        case .card where selectedCategories.contains(.cards):
            document.parentId.map { Destination(module: .table, itemId: stableId("\($0)#cards")) }
        case .adventure where selectedCategories.contains(.adventures):
            Destination(module: .adventure, itemId: stableId("\(document.id)#adventure"))
        case .combat where selectedCategories.contains(.combats):
            Destination(module: .adventure, itemId: stableId("\(document.id)#combat"))
        case .combatant where selectedCategories.contains(.combats):
            document.parentId.map { Destination(module: .adventure, itemId: stableId("\($0)#combat")) }
        case .macro where selectedCategories.contains(.macros):
            Destination(module: .adventure, itemId: stableId("\(document.id)#macro"))
        default: nil
        }
    }

    func module(for path: String) -> NetworkModules? {
        if let plan = FoundryMediaNormalizer.plan(forPackagedPath: path) {
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

    /// Canonical key of a path inside the package (`logicalPath`, `packagePath`): a zip entry
    /// path, not a URL. `#` and `?` are ordinary file name characters there (`Token #1.webp`), so
    /// nothing is cut. Path case stays intact: packages can be authored on a case-sensitive file
    /// system, so a case-folded path is only safe as a secondary alias.
    func canonicalResourcePath(_ path: String) -> String {
        normalizedResourcePath(path.removingPercentEncoding ?? path)
    }

    /// Canonical key of a reference found inside a document, which may be a URL: the query and
    /// fragment are cut first, the percent-decoding comes second (so an encoded `%23` stays part
    /// of the name), as `FoundryMediaNormalizer.canonicalPath` does.
    func canonicalReferencePath(_ path: String) -> String {
        let cut = path.prefix { $0 != "?" && $0 != "#" }
        let text = String(cut)
        return normalizedResourcePath(text.removingPercentEncoding ?? text)
    }

    private func normalizedResourcePath(_ path: String) -> String {
        path.replacing("\\", with: "/")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    func resourceAlias(_ path: String) -> String {
        canonicalResourcePath(path).lowercased()
    }

    func referenceAlias(_ path: String) -> String {
        canonicalReferencePath(path).lowercased()
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
        if let optionalHTML, let cached = plainTextCache[optionalHTML] { return cached }
        return FoundryTextDecoder.plainText(fromHTML: optionalHTML)
    }

    /// Imported text must not form a link of its own, a web link or one of the app's item links:
    /// `](` and `://` are split by a zero-width space, as the rule factory's text boundary does.
    /// It runs after the decoder (which strips the zero-width space) and before the Foundry
    /// links are rewritten, so only the links the mapper itself writes stay live.
    /// See CODE_AUDIT_28 §6.2.
    nonisolated static func neutralizingLinks(_ text: String) -> String {
        guard text.contains("](") || text.contains("://") else { return text }
        return text
            .replacing("](", with: "]\u{200B}(")
            .replacing("://", with: ":\u{200B}//")
    }

    /// Decoded package text that may not form a link and is not searched for Foundry links: names,
    /// reference targets, pack and document ids, effect statuses and change paths. Only the links
    /// the mapper writes itself (`markdownLink`) stay live. See CODE_AUDIT_29 §6.1.
    func inertText(_ optionalHTML: String?) -> String {
        Self.neutralizingLinks(sanitizedFoundryText(optionalHTML))
    }

    func safeText(_ optionalHTML: String?) -> String {
        rewriteFoundryLinks(Self.neutralizingLinks(sanitizedFoundryText(optionalHTML)))
    }

    func decodedFoundryText(_ text: String?) -> String {
        guard let text else { return "" }
        return rewriteFoundryLinks(Self.neutralizingLinks(
            FoundryTextDecoder.decodedText(text)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        ))
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
        // Most strings hold no link at all: skip the expression for them. See CODE_AUDIT_26 §7.19.
        guard input.contains("@"), let expression = FoundryMapperPatterns.foundryLink else {
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
        // `LinkBuilder.markdown` escapes the brackets; a line break would end the link.
        let singleLine = name
            .replacing("\n", with: " ")
            .replacing("\r", with: " ")
        return LinkBuilder.markdown(name: singleLine, module: module, itemId: itemId)
    }

    func inertCodeBlock(_ source: String) -> String {
        // Four backticks safely contain normal triple-backtick source. If a macro contains a
        // longer run, extend the delimiter until it cannot terminate the block.
        // See CODE_AUDIT_26 §5.126.
        var fenceLength = 4
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
                    "\(inertText(key)): \(presentedFoundryValue($0))"
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
            initiative.map { "Initiative: \(FoundryStoredText.number($0))" },
            "Defeated: \(defeated ? "yes" : "no")",
            "Hidden: \(hidden ? "yes" : "no")"
        ].compactMap { $0 }.joined(separator: "\n")
    }

    func simpleModifier(_ formula: String) -> Double {
        let withoutDice = formula.replacing(/([0-9]*)[dD]([0-9]+)/, with: "")
        guard let expression = FoundryMapperPatterns.signedNumber else {
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


/// The expressions the mapper uses for every description, entry and formula, compiled once. They
/// were rebuilt on each call, which dominated the mapping of a package with tens of thousands of
/// strings. See CODE_AUDIT_26 §7.19.
enum FoundryMapperPatterns {
    static let foundryLink: NSRegularExpression? = {
        let linkTypes = [
            "UUID", "Actor", "Item", "Scene", "JournalEntry", "JournalEntryPage",
            "RollTable", "TableResult", "Playlist", "PlaylistSound", "Cards", "Card",
            "Adventure", "Combat", "Macro", "Compendium",
        ].joined(separator: "|")
        return try? NSRegularExpression(
            pattern: #"@("# + linkTypes + #")\[([^\]\r\n]+)\](?:\{([^}\r\n]+)\})?"#
        )
    }()

    static let signedNumber = try? NSRegularExpression(pattern: #"[+-]\s*[0-9]+(?:\.[0-9]+)?"#)

    /// A formula MasterRPG can represent exactly: additive dice plus a numeric modifier.
    static let supportedFormula = try? NSRegularExpression(
        pattern: #"^\s*[0-9]*[dD][0-9]+(?:\s*(?:\+\s*[0-9]*[dD][0-9]+|[+-]\s*[0-9]+(?:\.[0-9]+)?))*\s*$"#
    )

    static let dieMatch = try? NSRegularExpression(pattern: #"([0-9]*)[dD]([0-9]+)"#)
}

/// Text that is written into imported items. Items sync through CloudKit and the importer compares
/// them with what is already in the library, so the same world has to produce the same bytes on
/// every device: a fixed locale for numbers and UTC ISO-8601 for dates, never the device's
/// formatting (`1,000` against `1.000`). See CODE_AUDIT §5.15.
enum FoundryStoredText {
    static func number(_ value: Double) -> String {
        value.formatted(.number.grouping(.never).locale(Locale(identifier: "en_US_POSIX")))
    }

    static func date(_ value: Date) -> String {
        value.formatted(.iso8601)
    }
}
