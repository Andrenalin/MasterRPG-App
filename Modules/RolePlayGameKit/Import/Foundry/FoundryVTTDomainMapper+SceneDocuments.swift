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

// The scene document mapping, split out of FoundryVTTDomainMapper+Documents.swift. See CODE_AUDIT_29 §9.9.

extension FoundryMappingState {
    func mapScene(_ document: FoundryDocument) async throws {
        guard let geometry = FoundryProjectionGeometry.sceneGeometry(in: document.rawData) else {
            emitGeometryWarning(.scene)
            rawOnlyDocumentIds.insert(document.id)
            return
        }
        let levels = document.embeddedDocuments.filter { $0.documentType == .level }
        if !levels.isEmpty {
            try await mapLeveledScene(document, levels: levels, geometry: geometry)
            return
        }

        let id = stableId("\(document.id)#map")
        let imagePath = document.rawData.value(at: "background.src")?.stringValue ?? document.imagePath
        let photoId = mediaId(path: imagePath, module: .photo)
        let ambientAudioLinks = projectedAmbientAudioLinks(
            in: document.embeddedDocuments.filter { $0.documentType == .ambientSound }
        )
        let tokens = document.embeddedDocuments.filter { $0.documentType == .token }
        let mappedPins = tokens.compactMap { token -> (source: FoundryDocument, model: MapPinModel)? in
            guard let pin = tokenPin(token, gridSize: geometry.gridSize) else {
                emitGeometryWarning(.token)
                rawOnlyDocumentIds.insert(token.id)
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
            photoId: photoId,
            width: geometry.width,
            height: geometry.height,
            mapPins: mappedPins.map(\.model),
            walls: walls,
            hexMapScale: geometry.gridSize,
            parentId: folderId(for: document, module: .map)
        )
        add(model, module: .map, sourceId: document.id)
        for pin in mappedPins {
            recordMapping(sourceId: pin.source.id, module: .map, itemId: id, entryId: pin.model.id)
        }
        for wall in mappedWalls {
            recordMapping(sourceId: wall.source.id, module: .map, itemId: id, entryId: wall.model.id)
        }
        for child in document.embeddedDocuments where !sceneHandledTypes.contains(child.documentType) {
            rawOnlyDocumentIds.insert(child.id)
        }
    }

    func mapLeveledScene(
        _ document: FoundryDocument,
        levels: [FoundryDocument],
        geometry: FoundrySceneProjectionGeometry
    ) async throws {
        let groupId = stableId("\(document.id)#level-group")
        let group = MapModel(
            id: groupId,
            name: document.name,
            description: safeText(document.descriptionHTML),
            tags: foundryTags(document),
            category: .folder,
            parentId: folderId(for: document, module: .map)
        )
        add(group, module: .map, sourceId: "\(document.id)#level-group")

        let initialLevel = initialLevel(in: document, levels: levels)
        let initialDocumentId = initialLevel.documentId
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
            let isInitial = level.documentId == initialDocumentId
            let id = levelMapIds[level.id] ?? stableId("\(level.id)#level-map")
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
                    rawOnlyDocumentIds.insert(token.id)
                    return nil
                }
                return (token, pin)
            }
            let mappedWalls = (wallsByLevel[level.id] ?? []).compactMap { wall in
                mapWall(
                    wall,
                    minimumElevation: minimumElevation,
                    maximumElevation: maximumElevation,
                    levelIdentifier: level.documentId,
                    identitySuffix: level.id
                ).map { (source: wall, model: $0) }
            }
            var description = safeText(document.descriptionHTML)
            let elevation = [
                minimumElevation.map { "bottom \(FoundryStoredText.number($0))" },
                maximumElevation.map { "top \(FoundryStoredText.number($0))" }
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
                photoId: mediaId(path: backgroundPath, module: .photo),
                width: geometry.width,
                height: geometry.height,
                mapPins: mappedPins.map(\.model),
                walls: mappedWalls.map(\.model),
                hexMapScale: geometry.gridSize,
                parentId: groupId
            )
            add(model, module: .map, sourceId: level.id)
            if isInitial {
                recordMapping(sourceId: document.id, module: .map, itemId: id)
            }
            for pin in mappedPins {
                recordMapping(sourceId: pin.source.id, module: .map, itemId: id, entryId: pin.model.id)
            }
            for wall in mappedWalls {
                recordMapping(sourceId: wall.source.id, module: .map, itemId: id, entryId: wall.model.id)
            }
        }

        for child in document.embeddedDocuments where !sceneHandledTypes.contains(child.documentType) {
            rawOnlyDocumentIds.insert(child.id)
        }
    }
}
