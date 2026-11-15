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
            rawOnlyDocumentIDs.insert(document.id)
        }
    }

    func mapActor(_ document: FoundryDocument) {
        let id = stableID("\(document.id)#character")
        var entries = hierarchicalEntries(
            document.rawData["system"],
            sourceID: document.id,
            ownerID: id,
            decisionOwnerID: id
        )
        for child in document.embeddedDocuments where child.documentType == .item {
            let childID = stableID("\(child.id)#character-item")
            let childModel = ValueModel(
                id: childID,
                name: child.name,
                description: safeText(child.descriptionHTML),
                tags: foundryTags(child),
                category: .item,
                displayState: DisplayStateMask.groupHidden.rawValue,
                photoId: mediaID(path: child.imagePath, module: .photo),
                entries: hierarchicalEntries(
                    child.rawData["system"],
                    sourceID: child.id,
                    ownerID: childID,
                    decisionOwnerID: id
                ),
                groupId: id
            )
            add(
                childModel,
                module: .value,
                sourceID: child.id,
                decisionOwnerID: id
            )
            entries.append(ValueEntryModel(
                id: stableID("\(document.id)#embedded-item#\(child.id)"),
                name: sanitizedFoundryText(child.name),
                type: .text,
                value: "",
                valueId: childID
            ))
        }
        let model = ValueModel(
            id: id,
            name: document.name,
            description: safeText(document.descriptionHTML),
            tags: foundryTags(document),
            category: actorCategory(document.subtype),
            photoId: mediaID(path: document.imagePath, module: .photo),
            entries: entries,
            parentId: folderID(for: document, module: .value)
        )
        add(model, module: .value, sourceID: document.id)
    }

    func mapItem(_ document: FoundryDocument) {
        if selectedCategories.contains(.items) {
            let id = stableID("\(document.id)#item")
            let model = ValueModel(
                id: id,
                name: document.name,
                description: safeText(document.descriptionHTML),
                tags: foundryTags(document),
                category: .item,
                photoId: mediaID(path: document.imagePath, module: .photo),
                entries: hierarchicalEntries(
                    document.rawData["system"],
                    sourceID: document.id,
                    ownerID: id,
                    decisionOwnerID: id
                ),
                parentId: folderID(for: document, module: .value)
            )
            add(model, module: .value, sourceID: document.id)
        }

        // System packages expose a richer normalized rule package and are projected above. World
        // and module Items do not, so preserve each standalone Item as an editable generic rule.
        if selectedCategories.contains(.rules), package.rulePackage == nil {
            let id = stableID("\(document.id)#rule")
            let filteredDocument = privacyFilteredDocumentsByID[document.id] ?? document
            let model = RuleModel.foundryDocument(
                id: id,
                name: filteredDocument.name,
                descriptionHTML: filteredDocument.descriptionHTML,
                tags: foundryTags(filteredDocument),
                documentType: filteredDocument.documentType.rawValue,
                subtype: filteredDocument.subtype ?? "",
                rawData: filteredDocument.rawData,
                parentId: folderID(for: document, module: .rule),
                packageIdentifier: packageIdentifier,
                identityNamespace: "external-source:\(sourceScopeID.uuidString.lowercased())#rule#\(document.id)"
            )
            prepareGenericRuleProjection(
                model,
                descriptionHTML: filteredDocument.descriptionHTML
            )
            add(model, module: .rule, sourceID: document.id)
        }
    }

    func mapScene(_ document: FoundryDocument) async throws {
        guard let geometry = FoundryProjectionGeometry.sceneGeometry(in: document.rawData) else {
            emitGeometryWarning(.scene)
            rawOnlyDocumentIDs.insert(document.id)
            return
        }
        let levels = document.embeddedDocuments.filter { $0.documentType == .level }
        if !levels.isEmpty {
            try await mapLeveledScene(document, levels: levels, geometry: geometry)
            return
        }

        let id = stableID("\(document.id)#map")
        let imagePath = document.rawData.value(at: "background.src")?.stringValue ?? document.imagePath
        let photoID = mediaID(path: imagePath, module: .photo)
        let ambientAudioLinks = projectedAmbientAudioLinks(
            in: document.embeddedDocuments.filter { $0.documentType == .ambientSound }
        )
        let tokens = document.embeddedDocuments.filter { $0.documentType == .token }
        let mappedPins = tokens.compactMap { token -> (source: FoundryDocument, model: MapPinModel)? in
            guard let pin = tokenPin(token, gridSize: geometry.gridSize) else {
                emitGeometryWarning(.token)
                rawOnlyDocumentIDs.insert(token.id)
                return nil
            }
            return (token, pin)
        }
        let wallDocuments = document.embeddedDocuments.filter { $0.documentType == .wall }
        let mappedWalls = wallDocuments.compactMap { wall in
            mapWall(wall).map { (source: wall, model: $0) }
        }
        let walls = mappedWalls.map(\.model)
        let model = MapModel(
            id: id,
            name: document.name,
            description: appendingAmbientAudio(
                ambientAudioLinks,
                to: safeText(document.descriptionHTML)
            ),
            tags: foundryTags(document),
            category: .dungeon,
            photoId: photoID,
            width: geometry.width,
            height: geometry.height,
            mapPins: mappedPins.map(\.model),
            walls: walls,
            hexMapScale: geometry.gridSize,
            parentId: folderID(for: document, module: .map)
        )
        add(model, module: .map, sourceID: document.id)
        for pin in mappedPins {
            recordMapping(sourceID: pin.source.id, module: .map, itemId: id, entryID: pin.model.id)
        }
        for wall in mappedWalls {
            recordMapping(sourceID: wall.source.id, module: .map, itemId: id, entryID: wall.model.id)
        }
        for child in document.embeddedDocuments where !sceneHandledTypes.contains(child.documentType) {
            rawOnlyDocumentIDs.insert(child.id)
        }
    }

    func mapLeveledScene(
        _ document: FoundryDocument,
        levels: [FoundryDocument],
        geometry: FoundrySceneProjectionGeometry
    ) async throws {
        let groupID = stableID("\(document.id)#level-group")
        let group = MapModel(
            id: groupID,
            name: document.name,
            description: safeText(document.descriptionHTML),
            tags: foundryTags(document),
            category: .folder,
            parentId: folderID(for: document, module: .map)
        )
        add(group, module: .map, sourceID: "\(document.id)#level-group")

        let initialLevel = initialLevel(in: document, levels: levels)
        let initialDocumentID = initialLevel.documentID
        let directTokens = document.embeddedDocuments
            .filter { $0.documentType == .token }
            .map { LeveledChild(document: $0, containingLevel: nil) }
        let nestedTokens = levels.flatMap { level in
            level.embeddedDocuments
                .filter { $0.documentType == .token }
                .map { LeveledChild(document: $0, containingLevel: level) }
        }
        let directWalls = document.embeddedDocuments
            .filter { $0.documentType == .wall }
            .map { LeveledChild(document: $0, containingLevel: nil) }
        let nestedWalls = levels.flatMap { level in
            level.embeddedDocuments
                .filter { $0.documentType == .wall }
                .map { LeveledChild(document: $0, containingLevel: level) }
        }
        let directAmbientSounds = document.embeddedDocuments
            .filter { $0.documentType == .ambientSound }
            .map { LeveledChild(document: $0, containingLevel: nil) }
        let nestedAmbientSounds = levels.flatMap { level in
            level.embeddedDocuments
                .filter { $0.documentType == .ambientSound }
                .map { LeveledChild(document: $0, containingLevel: level) }
        }
        let tokensByLevel = try await assignLevelMembership(
            directTokens + nestedTokens,
            levels: levels,
            initialLevel: initialLevel,
            kind: String(localized: "Token", bundle: .module)
        )
        let wallsByLevel = try await assignLevelMembership(
            directWalls + nestedWalls,
            levels: levels,
            initialLevel: initialLevel,
            kind: String(localized: "Wall", bundle: .module)
        )
        let ambientSoundsByLevel = try await assignLevelMembership(
            directAmbientSounds + nestedAmbientSounds,
            levels: levels,
            initialLevel: initialLevel,
            kind: String(localized: "Ambient sound", bundle: .module)
        )

        for level in levels {
            try await cooperativeCheckpoint()
            let isInitial = level.documentID == initialDocumentID
            let id = levelMapIDs[level.id] ?? stableID("\(level.id)#level-map")
            let backgroundPath = level.rawData.value(at: "background.src")?.stringValue
                ?? document.rawData.value(at: "background.src")?.stringValue
                ?? document.imagePath
            let foregroundPath = level.rawData.value(at: "foreground.src")?.stringValue
                ?? document.rawData.value(at: "foreground.src")?.stringValue
            let minimumElevation = projectedLevelElevation(level.rawData.value(at: "elevation.bottom"))
            let maximumElevation = projectedLevelElevation(level.rawData.value(at: "elevation.top"))
            let tokens = tokensByLevel[level.id] ?? []
            let mappedPins = tokens.compactMap { token -> (source: FoundryDocument, model: MapPinModel)? in
                guard let pin = tokenPin(token, gridSize: geometry.gridSize) else {
                    emitGeometryWarning(.token)
                    rawOnlyDocumentIDs.insert(token.id)
                    return nil
                }
                return (token, pin)
            }
            let mappedWalls = (wallsByLevel[level.id] ?? []).compactMap { wall in
                mapWall(
                    wall,
                    minimumElevation: minimumElevation,
                    maximumElevation: maximumElevation,
                    levelIdentifier: level.documentID,
                    identitySuffix: level.id
                ).map { (source: wall, model: $0) }
            }
            var description = safeText(document.descriptionHTML)
            let elevation = [
                minimumElevation.map { "bottom \($0.formatted())" },
                maximumElevation.map { "top \($0.formatted())" }
            ].compactMap { $0 }.joined(separator: ", ")
            if !elevation.isEmpty {
                description += "\(description.isEmpty ? "" : "\n\n")Elevation: \(elevation)"
            }
            if let foreground = assetLink(path: foregroundPath) {
                description += "\(description.isEmpty ? "" : "\n\n")Foreground: \(foreground)"
            }
            description = appendingAmbientAudio(
                projectedAmbientAudioLinks(in: ambientSoundsByLevel[level.id] ?? []),
                to: description
            )
            let model = MapModel(
                id: id,
                name: levels.count == 1 ? document.name : "\(document.name) — \(level.name)",
                description: description,
                tags: foundryTags(document) + ["Foundry Level"],
                category: .dungeon,
                photoId: mediaID(path: backgroundPath, module: .photo),
                width: geometry.width,
                height: geometry.height,
                mapPins: mappedPins.map(\.model),
                walls: mappedWalls.map(\.model),
                hexMapScale: geometry.gridSize,
                parentId: groupID
            )
            add(model, module: .map, sourceID: level.id)
            if isInitial {
                recordMapping(sourceID: document.id, module: .map, itemId: id)
            }
            for pin in mappedPins {
                recordMapping(sourceID: pin.source.id, module: .map, itemId: id, entryID: pin.model.id)
            }
            for wall in mappedWalls {
                recordMapping(sourceID: wall.source.id, module: .map, itemId: id, entryID: wall.model.id)
            }
        }

        for child in document.embeddedDocuments where !sceneHandledTypes.contains(child.documentType) {
            rawOnlyDocumentIDs.insert(child.id)
        }
    }

    func mapJournal(_ document: FoundryDocument) {
        let id = stableID("\(document.id)#journal")
        let model = AdventureModel.empty(id)
        model.name = document.name
        model.description = safeText(document.descriptionHTML)
        model.tags = foundryTags(document)
        model.category = .adventure
        model.parentId = folderID(for: document, module: .adventure)
        let pages = document.embeddedDocuments.filter { $0.documentType == .journalEntryPage }
        if pages.isEmpty {
            model.entries = [AdventureEntryModel(
                id: stableID("\(document.id)#content"),
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
                    id: stableID("\(page.id)#entry"),
                    name: sanitizedFoundryText(page.name),
                    content: rewriteFoundryLinks(content)
                )
                recordMapping(sourceID: page.id, module: .adventure, itemId: id, entryID: entry.id)
                return entry
            }
        }
        add(model, module: .adventure, sourceID: document.id)
    }

    func mapRollTable(_ document: FoundryDocument) {
        let tableID = stableID("\(document.id)#table")
        let formula = document.rawData["formula"]?.stringValue
        let diceID = formula.flatMap { createDice(formula: $0, name: document.name, sourceID: document.id) }
        let model = TableModel.empty(tableID)
        model.name = document.name
        model.description = safeText(document.descriptionHTML)
        model.tags = foundryTags(document)
        model.category = tableCategory(document)
        model.tableType = diceID == nil ? .list : .dice
        model.diceId = diceID
        model.parentId = folderID(for: document, module: .table)
        model.entries = document.embeddedDocuments
            .filter { $0.documentType == .tableResult }
            .map { result in
                var entry = TableEntryModel.empty(stableID("\(result.id)#table-entry"))
                entry.name = sanitizedFoundryText(result.name)
                let range = result.rawData["range"]?.arrayValue?.compactMap(number).map { $0.formatted() }.joined(separator: "–")
                let weight = number(result.rawData["weight"])
                var details = safeText(result.descriptionHTML)
                if details.isEmpty { details = result.rawData["text"]?.stringValue.map(safeText) ?? "" }
                if let link = assetLink(path: result.imagePath) {
                    details += "\(details.isEmpty ? "" : "\n")\(link)"
                }
                let metadata = [
                    range.map { "Range: \($0)" },
                    weight.map { "Weight: \($0.formatted())" }
                ].compactMap { $0 }.joined(separator: "; ")
                entry.content = [details, metadata].filter { !$0.isEmpty }.joined(separator: "\n")
                recordMapping(sourceID: result.id, module: .table, itemId: tableID, entryID: entry.id)
                return entry
            }
        add(model, module: .table, sourceID: document.id)
    }

    func mapPlaylist(_ document: FoundryDocument) {
        let id = stableID("\(document.id)#playlist")
        let model = AudioModel.empty(id)
        model.name = document.name
        model.description = safeText(document.descriptionHTML)
        model.tags = foundryTags(document)
        model.category = .playlist
        model.parentId = folderID(for: document, module: .audio)
        model.entries = document.embeddedDocuments
            .filter { $0.documentType == .playlistSound }
            .compactMap { sound in
                let path = sound.rawData["path"]?.stringValue ?? sound.rawData["src"]?.stringValue
                guard let audioID = mediaID(path: path, module: .audio) else {
                    rawOnlyDocumentIDs.insert(sound.id)
                    return nil
                }
                recordMapping(sourceID: sound.id, module: .audio, itemId: audioID)
                return AudioEntryModel(
                    id: stableID("\(document.id)#sound-edge#\(sound.id)"),
                    audioId: audioID
                )
            }
        add(model, module: .audio, sourceID: document.id)
    }

    func mapStandaloneAudio(_ document: FoundryDocument) {
        let path = firstString(
            document.rawData,
            paths: ["path", "src", "sound.src", "source"]
        )
        guard let audioID = mediaID(path: path, module: .audio) else {
            rawOnlyDocumentIDs.insert(document.id)
            return
        }
        recordMapping(sourceID: document.id, module: .audio, itemId: audioID)
    }

    func mapCards(_ document: FoundryDocument) {
        let id = stableID("\(document.id)#cards")
        let model = TableModel.empty(id)
        model.name = document.name
        model.description = safeText(document.descriptionHTML)
        model.tags = foundryTags(document)
        model.category = .collection
        model.parentId = folderID(for: document, module: .table)
        model.entries = document.embeddedDocuments
            .filter { $0.documentType == .card }
            .map { card in
                var entry = TableEntryModel.empty(stableID("\(card.id)#card-entry"))
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
                recordMapping(sourceID: card.id, module: .table, itemId: id, entryID: entry.id)
                return entry
            }
        add(model, module: .table, sourceID: document.id)
    }

    func mapAdventure(_ document: FoundryDocument) async throws {
        for child in document.embeddedDocuments {
            try await cooperativeCheckpoint()
            try await mapDocument(child)
        }
        let id = stableID("\(document.id)#adventure")
        let model = AdventureModel.empty(id)
        model.name = document.name
        model.description = safeText(document.descriptionHTML)
        model.tags = foundryTags(document)
        model.category = .campaign
        model.parentId = folderID(for: document, module: .adventure)
        model.entries = document.embeddedDocuments.flatMap { child in
            (mappingReferences[child.id] ?? []).map { reference in
                AdventureEntryModel(
                    id: stableID("\(document.id)#link#\(child.id)#\(reference.module.token)#\(reference.itemId)"),
                    name: sanitizedFoundryText(child.name),
                    content: markdownLink(
                        name: sanitizedFoundryText(child.name),
                        module: reference.module,
                        itemId: reference.itemId
                    )
                )
            }
        }
        add(model, module: .adventure, sourceID: document.id)
    }

    func mapCombat(_ document: FoundryDocument) {
        let id = stableID("\(document.id)#combat")
        let model = AdventureModel.empty(id)
        model.name = document.name.isEmpty ? "Combat" : document.name
        model.description = "Imported Foundry combat state. It is reference material and does not become a live MasterRPG encounter."
        model.tags = foundryTags(document)
        model.category = .scenario
        model.parentId = folderID(for: document, module: .adventure)
        model.entries = document.embeddedDocuments
            .filter { $0.documentType == .combatant }
            .map { combatant in
                let entry = AdventureEntryModel(
                    id: stableID("\(combatant.id)#combat-entry"),
                    name: sanitizedFoundryText(combatant.name),
                    content: combatantSummary(combatant)
                )
                recordMapping(sourceID: combatant.id, module: .adventure, itemId: id, entryID: entry.id)
                return entry
            }
        add(model, module: .adventure, sourceID: document.id)
    }

    func mapMacro(_ document: FoundryDocument) {
        let id = stableID("\(document.id)#macro")
        let model = AdventureModel.empty(id)
        model.name = document.name
        model.description = "Foundry macro imported as non-executable text."
        model.tags = foundryTags(document) + ["Non-executable"]
        model.category = .supplement
        model.parentId = folderID(for: document, module: .adventure)
        let command = document.rawData["command"]?.stringValue ?? ""
        model.entries = [AdventureEntryModel(
            id: stableID("\(document.id)#macro-source"),
            name: "Source (never executed)",
            content: inertCodeBlock(command)
        )]
        add(model, module: .adventure, sourceID: document.id, warnings: [String(localized: "Macro code is stored as text and is never executed.", bundle: .module)])
    }

    func mapChatTranscript(_ collection: FoundryDocumentCollection) {
        let messages = collection.documents.filter { $0.documentType == .chatMessage }
        guard !messages.isEmpty else { return }
        let id = stableID("\(collection.id)#chat-transcript")
        let model = AdventureModel.empty(id)
        model.name = "\(sanitizedFoundryText(collection.label)) – Chat transcript"
        model.description = "Foundry chat history. Review private, blind, and whispered messages before sharing."
        model.tags = ["Foundry VTT", "Private import"]
        model.category = .supplement
        model.entries = messages.map { message in
            let speaker = message.rawData.value(at: "speaker.alias")?.stringValue ?? message.name
            let timestamp = message.rawData["timestamp"]?.integerValue
            let content = message.rawData["content"]?.stringValue ?? message.descriptionHTML ?? ""
            let dateText = timestamp.map { Date(timeIntervalSince1970: TimeInterval($0 / 1_000)).formatted(date: .abbreviated, time: .shortened) }
            let entry = AdventureEntryModel(
                id: stableID("\(message.id)#chat-entry"),
                name: [speaker, dateText]
                    .compactMap { $0 }
                    .map(sanitizedFoundryText)
                    .filter { !$0.isEmpty }
                    .joined(separator: " – "),
                content: rewriteFoundryLinks(safeText(content))
            )
            recordMapping(sourceID: message.id, module: .adventure, itemId: id, entryID: entry.id)
            return entry
        }
        add(model, module: .adventure, sourceID: "\(collection.id)#chat")
    }
}
