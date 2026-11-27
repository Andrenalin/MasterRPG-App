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

// The journal, card, combat, macro and chat mapping, split out of FoundryVTTDomainMapper+Documents.swift. See CODE_AUDIT_29 §9.9.

extension FoundryMappingState {
    func mapJournal(_ document: FoundryDocument) {
        let id = stableId("\(document.id)#journal")
        let model = AdventureModel.empty(id)
        model.name = document.name
        model.description = safeText(document.descriptionHTML)
        model.tags = foundryTags(document)
        model.category = .adventure
        model.parentId = folderId(for: document, module: .adventure)
        let pages = document.embeddedDocuments.filter { $0.documentType == .journalEntryPage }
        if pages.isEmpty {
            model.entries = [AdventureEntryModel(
                id: stableId("\(document.id)#content"),
                name: sanitizedFoundryText(document.name),
                content: safeText(document.descriptionHTML)
            )]
        } else {
            model.entries = pages.map { page in
                var content = safeText(page.descriptionHTML)
                let sourcePath = page.rawData["src"]?.stringValue
                    ?? page.rawData.value(at: "image.src")?.stringValue
                    ?? page.rawData.value(at: "video.src")?.stringValue
                if let link = assetLink(path: sourcePath) {
                    content += "\(content.isEmpty ? "" : "\n\n")\(link)"
                }
                let entry = AdventureEntryModel(
                    id: stableId("\(page.id)#entry"),
                    name: sanitizedFoundryText(page.name),
                    // `safeText` rewrote the links already. See CODE_AUDIT_29 §9.6.
                    content: content
                )
                recordMapping(sourceId: page.id, module: .adventure, itemId: id, entryId: entry.id)
                return entry
            }
        }
        add(model, module: .adventure, sourceId: document.id)
    }

    func mapCards(_ document: FoundryDocument) {
        let id = stableId("\(document.id)#cards")
        let model = TableModel.empty(id)
        model.name = document.name
        model.description = safeText(document.descriptionHTML)
        model.tags = foundryTags(document)
        model.category = .collection
        model.parentId = folderId(for: document, module: .table)
        model.entries = document.embeddedDocuments
            .filter { $0.documentType == .card }
            .map { card in
                var entry = TableEntryModel.empty(stableId("\(card.id)#card-entry"))
                entry.name = sanitizedFoundryText(card.name)
                var content = safeText(card.descriptionHTML)
                if let link = assetLink(path: card.imagePath) {
                    content += "\(content.isEmpty ? "" : "\n")\(link)"
                }
                let state = [
                    card.rawData["drawn"]?.boolValue.map { "Drawn: \($0 ? "yes" : "no")" },
                    card.rawData["sort"]?.integerValue.map { "Sort: \($0)" }
                ].compactMap { $0 }.joined(separator: "; ")
                entry.content = [content, state].filter { !$0.isEmpty }.joined(separator: "\n")
                recordMapping(sourceId: card.id, module: .table, itemId: id, entryId: entry.id)
                return entry
            }
        add(model, module: .table, sourceId: document.id)
    }

    func mapCombat(_ document: FoundryDocument) {
        let id = stableId("\(document.id)#combat")
        let model = AdventureModel.empty(id)
        model.name = document.name.isEmpty ? "Combat" : document.name
        model.description = "Imported Foundry combat state. It is reference material and does not become a live MasterRPG encounter."
        model.tags = foundryTags(document)
        model.category = .scenario
        model.parentId = folderId(for: document, module: .adventure)
        model.entries = document.embeddedDocuments
            .filter { $0.documentType == .combatant }
            .map { combatant in
                let entry = AdventureEntryModel(
                    id: stableId("\(combatant.id)#combat-entry"),
                    name: sanitizedFoundryText(combatant.name),
                    content: combatantSummary(combatant)
                )
                recordMapping(sourceId: combatant.id, module: .adventure, itemId: id, entryId: entry.id)
                return entry
            }
        add(model, module: .adventure, sourceId: document.id)
    }

    func mapMacro(_ document: FoundryDocument) {
        let id = stableId("\(document.id)#macro")
        let model = AdventureModel.empty(id)
        model.name = document.name
        model.description = "Foundry macro imported as non-executable text."
        model.tags = foundryTags(document) + ["Non-executable"]
        model.category = .supplement
        model.parentId = folderId(for: document, module: .adventure)
        let command = document.rawData["command"]?.stringValue ?? ""
        model.entries = [AdventureEntryModel(
            id: stableId("\(document.id)#macro-source"),
            name: "Source (never executed)",
            content: inertCodeBlock(command)
        )]
        add(model, module: .adventure, sourceId: document.id, warnings: [String(localized: "Macro code is stored as text and is never executed.", bundle: .module)])
    }

    func mapChatTranscript(_ collection: FoundryDocumentCollection) {
        let messages = collection.documents.filter { $0.documentType == .chatMessage }
        guard !messages.isEmpty else { return }
        let id = stableId("\(collection.id)#chat-transcript")
        let model = AdventureModel.empty(id)
        model.name = "\(sanitizedFoundryText(collection.label)) – Chat transcript"
        model.description = "Foundry chat history. Review private, blind, and whispered messages before sharing."
        model.tags = ["Foundry VTT", "Private import"]
        model.category = .supplement
        model.entries = messages.map { message in
            let speaker = message.rawData.value(at: "speaker.alias")?.stringValue ?? message.name
            let timestamp = message.rawData["timestamp"]?.integerValue
            let content = message.rawData["content"]?.stringValue ?? message.descriptionHTML ?? ""
            let dateText = timestamp.map { FoundryStoredText.date(Date(timeIntervalSince1970: TimeInterval($0 / 1_000))) }
            let entry = AdventureEntryModel(
                id: stableId("\(message.id)#chat-entry"),
                name: [speaker, dateText]
                    .compactMap { $0 }
                    .map(sanitizedFoundryText)
                    .filter { !$0.isEmpty }
                    .joined(separator: " – "),
                content: safeText(content)
            )
            recordMapping(sourceId: message.id, module: .adventure, itemId: id, entryId: entry.id)
            return entry
        }
        add(model, module: .adventure, sourceId: "\(collection.id)#chat")
    }
}
