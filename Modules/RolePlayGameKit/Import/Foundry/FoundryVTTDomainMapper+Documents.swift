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

// MARK: - Document dispatch

extension FoundryMappingState {
    func mapDocument(_ document: FoundryDocument) async throws {
        switch document.documentType {
        case .actor where selectedCategories.contains(.actors):
            mapActor(document)
        case .item where selectedCategories.contains(.items)
            || (selectedCategories.contains(.rules) && package.rulePackage == nil):
            mapItem(document)
        case .scene where selectedCategories.contains(.scenes):
            try await mapScene(document)
        case .journalEntry where selectedCategories.contains(.journals):
            mapJournal(document)
        case .rollTable where selectedCategories.contains(.tables):
            mapRollTable(document)
        case .playlist where selectedCategories.contains(.playlists):
            mapPlaylist(document)
        case .playlistSound where selectedCategories.contains(.playlists):
            mapStandaloneAudio(document)
        case .ambientSound where selectedCategories.contains(.scenes):
            mapStandaloneAudio(document)
        case .cards where selectedCategories.contains(.cards):
            mapCards(document)
        case .adventure where selectedCategories.contains(.adventures):
            try await mapAdventure(document)
        case .combat where selectedCategories.contains(.combats):
            mapCombat(document)
        case .macro where selectedCategories.contains(.macros):
            mapMacro(document)
        case .folder, .level, .journalEntryPage, .tableResult, .card, .user,
             .token, .wall, .ambientLight, .activeEffect, .combatant:
            break
        default:
            rawOnlyDocumentIds.insert(document.id)
        }
    }

    func mapActor(_ document: FoundryDocument) {
        let id = stableId("\(document.id)#character")
        var entries = hierarchicalEntries(
            document.rawData["system"],
            sourceId: document.id,
            ownerId: id,
            decisionOwnerId: id
        )
        for child in document.embeddedDocuments where child.documentType == .item {
            let childId = stableId("\(child.id)#character-item")
            let childModel = ValueModel(
                id: childId,
                name: child.name,
                description: safeText(child.descriptionHTML),
                tags: foundryTags(child),
                category: .item,
                displayState: DisplayStateMask.groupHidden.rawValue,
                photoId: mediaId(path: child.imagePath, module: .photo),
                entries: hierarchicalEntries(
                    child.rawData["system"],
                    sourceId: child.id,
                    ownerId: childId,
                    decisionOwnerId: id
                ),
                groupId: id
            )
            add(
                childModel,
                module: .value,
                sourceId: child.id,
                decisionOwnerId: id
            )
            entries.append(ValueEntryModel(
                id: stableId("\(document.id)#embedded-item#\(child.id)"),
                name: sanitizedFoundryText(child.name),
                type: .text,
                value: "",
                valueId: childId
            ))
        }
        let model = ValueModel(
            id: id,
            name: document.name,
            description: safeText(document.descriptionHTML),
            tags: foundryTags(document),
            category: actorCategory(document.subtype),
            photoId: mediaId(path: document.imagePath, module: .photo),
            entries: entries,
            parentId: folderId(for: document, module: .value)
        )
        add(model, module: .value, sourceId: document.id)
    }

    func mapItem(_ document: FoundryDocument) {
        if selectedCategories.contains(.items) {
            let id = stableId("\(document.id)#item")
            let model = ValueModel(
                id: id,
                name: document.name,
                description: safeText(document.descriptionHTML),
                tags: foundryTags(document),
                category: .item,
                photoId: mediaId(path: document.imagePath, module: .photo),
                entries: hierarchicalEntries(
                    document.rawData["system"],
                    sourceId: document.id,
                    ownerId: id,
                    decisionOwnerId: id
                ),
                parentId: folderId(for: document, module: .value)
            )
            add(model, module: .value, sourceId: document.id)
        }

        // System packages expose a richer normalized rule package and are projected above. World
        // and module Items do not, so preserve each standalone Item as an editable generic rule.
        if selectedCategories.contains(.rules), package.rulePackage == nil {
            let id = stableId("\(document.id)#rule")
            let filteredDocument = privacyFilteredDocumentsById[document.id] ?? document
            let model = RuleModel.foundryDocument(
                id: id,
                name: filteredDocument.name,
                descriptionHTML: filteredDocument.descriptionHTML,
                tags: foundryTags(filteredDocument),
                documentType: filteredDocument.documentType.rawValue,
                subtype: filteredDocument.subtype ?? "",
                rawData: filteredDocument.rawData,
                parentId: folderId(for: document, module: .rule),
                packageIdentifier: packageIdentifier,
                identityNamespace: "external-source:\(sourceScopeId.uuidString.lowercased())#rule#\(document.id)"
            )
            prepareGenericRuleProjection(
                model,
                descriptionHTML: filteredDocument.descriptionHTML
            )
            add(model, module: .rule, sourceId: document.id)
        }
    }

    func mapRollTable(_ document: FoundryDocument) {
        let tableId = stableId("\(document.id)#table")
        let formula = document.rawData["formula"]?.stringValue
        let diceId = formula.flatMap { createDice(formula: $0, name: document.name, sourceId: document.id) }
        let model = TableModel.empty(tableId)
        model.name = document.name
        model.description = safeText(document.descriptionHTML)
        model.tags = foundryTags(document)
        model.category = tableCategory(document)
        model.tableType = diceId == nil ? .list : .dice
        model.diceId = diceId
        model.parentId = folderId(for: document, module: .table)
        model.entries = document.embeddedDocuments
            .filter { $0.documentType == .tableResult }
            .map { result in
                var entry = TableEntryModel.empty(stableId("\(result.id)#table-entry"))
                entry.name = sanitizedFoundryText(result.name)
                let range = result.rawData["range"]?.arrayValue?.compactMap(number).map(FoundryStoredText.number).joined(separator: "–")
                let weight = number(result.rawData["weight"])
                var details = safeText(result.descriptionHTML)
                if details.isEmpty { details = result.rawData["text"]?.stringValue.map(safeText) ?? "" }
                if let link = assetLink(path: result.imagePath) {
                    details += "\(details.isEmpty ? "" : "\n")\(link)"
                }
                let metadata = [
                    range.map { "Range: \($0)" },
                    weight.map { "Weight: \(FoundryStoredText.number($0))" }
                ].compactMap { $0 }.joined(separator: "; ")
                entry.content = [details, metadata].filter { !$0.isEmpty }.joined(separator: "\n")
                recordMapping(sourceId: result.id, module: .table, itemId: tableId, entryId: entry.id)
                return entry
            }
        add(model, module: .table, sourceId: document.id)
    }

    func mapPlaylist(_ document: FoundryDocument) {
        let id = stableId("\(document.id)#playlist")
        let model = AudioModel.empty(id)
        model.name = document.name
        model.description = safeText(document.descriptionHTML)
        model.tags = foundryTags(document)
        model.category = .playlist
        model.parentId = folderId(for: document, module: .audio)
        model.entries = document.embeddedDocuments
            .filter { $0.documentType == .playlistSound }
            .compactMap { sound in
                let path = sound.rawData["path"]?.stringValue ?? sound.rawData["src"]?.stringValue
                guard let audioId = mediaId(path: path, module: .audio) else {
                    rawOnlyDocumentIds.insert(sound.id)
                    return nil
                }
                recordMapping(sourceId: sound.id, module: .audio, itemId: audioId)
                return AudioEntryModel(
                    id: stableId("\(document.id)#sound-edge#\(sound.id)"),
                    audioId: audioId
                )
            }
        add(model, module: .audio, sourceId: document.id)
    }

    func mapStandaloneAudio(_ document: FoundryDocument) {
        let path = firstString(
            document.rawData,
            paths: ["path", "src", "sound.src", "source"]
        )
        guard let audioId = mediaId(path: path, module: .audio) else {
            rawOnlyDocumentIds.insert(document.id)
            return
        }
        recordMapping(sourceId: document.id, module: .audio, itemId: audioId)
    }

    func mapAdventure(_ document: FoundryDocument) async throws {
        for child in document.embeddedDocuments {
            try await cooperativeCheckpoint()
            try await mapDocument(child)
        }
        let id = stableId("\(document.id)#adventure")
        let model = AdventureModel.empty(id)
        model.name = document.name
        model.description = safeText(document.descriptionHTML)
        model.tags = foundryTags(document)
        model.category = .campaign
        model.parentId = folderId(for: document, module: .adventure)
        // One entry per embedded document, linking the item it is projected to. Everything recorded
        // under a source id is not that item: field groups of an Actor or Item are hidden helper
        // models, and an Item is a Value and a Rule. The references are a `Set`, so taking all
        // of them linked the helpers and ordered the entries by the per-process hash seed.
        // See CODE_AUDIT §5.4.
        model.entries = document.embeddedDocuments.compactMap { child in
            guard let reference = adventureLinkReference(for: child) else { return nil }
            return AdventureEntryModel(
                id: stableId("\(document.id)#link#\(child.id)#\(reference.module.token)#\(reference.itemId)"),
                name: sanitizedFoundryText(child.name),
                content: markdownLink(
                    name: sanitizedFoundryText(child.name),
                    module: reference.module,
                    itemId: reference.itemId
                )
            )
        }
        add(model, module: .adventure, sourceId: document.id)
    }

    /// The projected item an Adventure entry for `child` links: the destination the importer
    /// predicts for it (the one links inside imported text resolve to), else the first
    /// non-auxiliary mapping in a fixed order. Auxiliary items follow their owner and are never
    /// linked on their own.
    func adventureLinkReference(for child: FoundryDocument) -> FoundryImportMappingReference? {
        let references = mappingReferences[child.id] ?? []
        if let destination = predictedDestination(for: child),
           let predicted = references.first(where: { $0.module == destination.module && $0.itemId == destination.itemId }) {
            return predicted
        }
        let auxiliaryIds = Set(items.filter(\.isAuxiliary).map(\.id))
        return references
            .filter { !auxiliaryIds.contains($0.itemId) }
            .min(by: mappingOrder)
    }

}
