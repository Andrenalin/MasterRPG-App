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

// MARK: - Scene conversion

extension FoundryMappingState {
    struct LeveledChild {
        let document: FoundryDocument
        let containingLevel: FoundryDocument?
    }

    var sceneHandledTypes: Set<FoundryDocumentType> {
        [.level, .token, .wall, .ambientSound]
    }

    func projectedAmbientAudioLinks(in sounds: [FoundryDocument]) -> [String] {
        sounds.compactMap { sound in
            let path = firstString(
                sound.rawData,
                paths: ["path", "src", "sound.src", "source"]
            )
            guard let path,
                  let resource = resource(matching: path),
                  let audioID = mediaID(path: path, module: .audio) else {
                rawOnlyDocumentIDs.insert(sound.id)
                return nil
            }
            recordMapping(sourceID: sound.id, module: .audio, itemId: audioID)
            let importedFilename = FoundryMediaNormalizer.plan(
                for: resource.logicalPath,
                expectedKind: .audio
            )?.suggestedFilename
            let documentName = sanitizedFoundryText(sound.name)
            let fallbackName = importedFilename
                ?? URL(filePath: resource.logicalPath).lastPathComponent
            let name = documentName.isEmpty ? fallbackName : documentName
            return markdownLink(name: name, module: .audio, itemId: audioID)
        }
    }

    func appendingAmbientAudio(_ links: [String], to description: String) -> String {
        guard !links.isEmpty else { return description }
        let section = "**Ambient audio**\n\(links.map { "- \($0)" }.joined(separator: "\n"))"
        return [description, section].filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    func initialLevel(in scene: FoundryDocument, levels: [FoundryDocument]) -> FoundryDocument {
        precondition(!levels.isEmpty)
        if let requested = foundryIdentifier(scene.rawData["initialLevel"]) {
            if let level = matchingLevel(requested, in: levels) {
                return level
            }
            warnings.append(String(localized: "Scene \(scene.name) names unknown initial level \(requested); the first source level is used instead.", bundle: .module))
        }

        // `embeddedDocuments` is sorted for stable presentation. Preserve Foundry's source-array
        // order for the semantic fallback required when Scene.initialLevel is absent or invalid.
        for sourceLevel in scene.rawData["levels"]?.arrayValue ?? [] {
            guard let identifier = foundryIdentifier(sourceLevel),
                  let level = matchingLevel(identifier, in: levels) else { continue }
            return level
        }
        return levels[0]
    }

    func assignLevelMembership(
        _ children: [LeveledChild],
        levels: [FoundryDocument],
        initialLevel: FoundryDocument,
        kind: String
    ) async throws -> [String: [FoundryDocument]] {
        var result: [String: [FoundryDocument]] = [:]
        for child in children {
            // This is the O(children × levels) hot spot the checkpoint guards: each
            // `matchingLevel` call below does a linear scan of `levels`. See CODE_AUDIT §5.14.
            try await cooperativeCheckpoint()
            let explicitIdentifier = explicitLevelIdentifier(in: child.document)
            let target: FoundryDocument?
            if let explicitIdentifier {
                target = matchingLevel(explicitIdentifier, in: levels)
                if target == nil {
                    warnings.append(String(localized: "\(kind) \(child.document.name) names unknown level \(explicitIdentifier); it remains only in the raw archive.", bundle: .module))
                    rawOnlyDocumentIDs.insert(child.document.id)
                }
            } else {
                target = child.containingLevel ?? initialLevel
            }
            guard let target else { continue }
            result[target.id, default: []].append(child.document)
        }
        return result
    }

    func explicitLevelIdentifier(in document: FoundryDocument) -> String? {
        let candidates = [
            document.rawData["level"],
            document.rawData["levelId"],
            document.rawData.value(at: "flags.levels.levelId"),
            document.rawData.value(at: "flags.levels.level"),
        ]
        return candidates.lazy.compactMap(foundryIdentifier).first
    }

    func matchingLevel(_ identifier: String, in levels: [FoundryDocument]) -> FoundryDocument? {
        levels.first { level in
            level.documentID == identifier
                || level.id == identifier
                || level.sourceUUID == identifier
                || level.rawData["uuid"]?.stringValue == identifier
        }
    }

    func foundryIdentifier(_ value: FoundryJSONValue?) -> String? {
        let identifier: String? = switch value {
        case .string(let value): value
        case .object(let object):
            object["_id"]?.stringValue
                ?? object["id"]?.stringValue
                ?? object["uuid"]?.stringValue
        default: nil
        }
        guard let identifier = identifier?.trimmingCharacters(in: .whitespacesAndNewlines),
              !identifier.isEmpty else { return nil }
        return identifier
    }

    func projectedLevelElevation(_ value: FoundryJSONValue?) -> Double? {
        guard let value else { return nil }
        guard let elevation = FoundryProjectionGeometry.coordinate(value) else {
            emitGeometryWarning(.levelElevation)
            return nil
        }
        return elevation
    }

    func emitGeometryWarning(_ warning: FoundryGeometryWarning) {
        guard emittedGeometryWarnings.insert(warning).inserted else { return }
        warnings.append(warning.message)
    }

    func tokenPin(_ token: FoundryDocument, gridSize: Double) -> MapPinModel? {
        guard let x = FoundryProjectionGeometry.coordinate(token.rawData["x"], defaultValue: 0),
              let y = FoundryProjectionGeometry.coordinate(token.rawData["y"], defaultValue: 0),
              let width = FoundryProjectionGeometry.tokenDimension(
                  token.rawData["width"],
                  defaultValue: 1
              ),
              let height = FoundryProjectionGeometry.tokenDimension(
                  token.rawData["height"],
                  defaultValue: 1
              ),
              let centerX = FoundryProjectionGeometry.tokenCenter(
                  origin: x,
                  gridUnits: width,
                  gridSize: gridSize
              ),
              let centerY = FoundryProjectionGeometry.tokenCenter(
                  origin: y,
                  gridUnits: height,
                  gridSize: gridSize
              ) else { return nil }
        let actorID = token.rawData["actorId"]?.stringValue.flatMap { actorsByDocumentID[$0] }
        let texture = token.rawData.value(at: "texture.src")?.stringValue ?? token.imagePath
        let units = max(width, height)
        let size: MapPinModel.MapPinSize = switch units {
        case ..<0.75: .tiny
        case ..<1: .small
        case ..<2: .normal
        case ..<3: .large
        case ..<4: .huge
        default: .colossal
        }
        return MapPinModel(
            id: stableID("\(token.id)#map-pin"),
            name: token.name,
            photoId: mediaID(path: texture, module: .photo),
            characterId: actorID,
            location: CGPoint(x: centerX, y: centerY),
            size: size,
            isShown: !(token.rawData["hidden"]?.boolValue ?? false),
            isDead: token.rawData.value(at: "overlayEffect")?.stringValue?.localizedCaseInsensitiveContains("dead") ?? false
        )
    }

    func mapWall(
        _ wall: FoundryDocument,
        minimumElevation: Double? = nil,
        maximumElevation: Double? = nil,
        levelIdentifier: String? = nil,
        identitySuffix: String? = nil
    ) -> MapWallModel? {
        guard let rawCoordinates = wall.rawData["c"]?.arrayValue, rawCoordinates.count >= 4 else {
            emitGeometryWarning(.wall)
            rawOnlyDocumentIDs.insert(wall.id)
            return nil
        }
        let coordinates = rawCoordinates.prefix(4).compactMap {
            FoundryProjectionGeometry.coordinate($0)
        }
        guard coordinates.count == 4,
              let movementRestriction = FoundryProjectionGeometry.exactInteger(
                  wall.rawData["move"],
                  defaultValue: 20
              ),
              let sightRestriction = FoundryProjectionGeometry.exactInteger(
                  wall.rawData["sight"],
                  defaultValue: 20
              ),
              let doorType = FoundryProjectionGeometry.exactInteger(
                  wall.rawData["door"],
                  defaultValue: 0
              ),
              let doorState = FoundryProjectionGeometry.exactInteger(
                  wall.rawData["ds"],
                  defaultValue: 0
              ) else {
            emitGeometryWarning(.wall)
            rawOnlyDocumentIDs.insert(wall.id)
            return nil
        }
        let rawMinimumElevation = firstValue(
            wall.rawData,
            paths: ["flags.wall-height.bottom", "flags.levels.rangeBottom"]
        )
        let rawMaximumElevation = firstValue(
            wall.rawData,
            paths: ["flags.wall-height.top", "flags.levels.rangeTop"]
        )
        let resolvedMinimumElevation: Double?
        if let rawMinimumElevation {
            guard let value = FoundryProjectionGeometry.coordinate(rawMinimumElevation) else {
                emitGeometryWarning(.wall)
                rawOnlyDocumentIDs.insert(wall.id)
                return nil
            }
            resolvedMinimumElevation = value
        } else {
            resolvedMinimumElevation = minimumElevation
        }
        let resolvedMaximumElevation: Double?
        if let rawMaximumElevation {
            guard let value = FoundryProjectionGeometry.coordinate(rawMaximumElevation) else {
                emitGeometryWarning(.wall)
                rawOnlyDocumentIDs.insert(wall.id)
                return nil
            }
            resolvedMaximumElevation = value
        } else {
            resolvedMaximumElevation = maximumElevation
        }
        let identity = identitySuffix.map { "\(wall.id)#wall#\($0)" } ?? "\(wall.id)#wall"
        let sourceIdentifier = identitySuffix.map { "\(wall.id)#level#\($0)" } ?? wall.id
        return MapWallModel(
            id: stableID(identity),
            sourceIdentifier: sourceIdentifier,
            start: CGPoint(x: coordinates[0], y: coordinates[1]),
            end: CGPoint(x: coordinates[2], y: coordinates[3]),
            movementRestriction: .init(rawValue: movementRestriction),
            sightRestriction: .init(rawValue: sightRestriction),
            doorType: .init(rawValue: doorType),
            doorState: .init(rawValue: doorState),
            minimumElevation: resolvedMinimumElevation,
            maximumElevation: resolvedMaximumElevation,
            levelIdentifier: firstString(wall.rawData, paths: ["flags.levels.levelId", "flags.levels.level"])
                ?? levelIdentifier,
            rawMetadata: wall.rawData
        )
    }
}
