// @copyright André Trettin

import CoreRPG
import CoreGraphics
import Foundation
import MapRPG
import PhotoRPG
import UniformTypeIdentifiers

@MainActor
struct UniversalVTTDomainMapper {
    func map(
        document: UniversalVTTDocument,
        sourceURL: URL,
        sourceScopeID: UUID,
        resourceLoader: @escaping FoundryResourceLoader
    ) async throws -> FoundryMappedImport {
        try Task.checkCancellation()
        await Task.yield()
        try Task.checkCancellation()
        let sourceName = FoundryTextDecoder.plainText(
            fromHTML: sourceURL.deletingPathExtension().lastPathComponent
        )
        let sourceIdentifier = "universal-vtt#\(sourceScopeID.uuidString.lowercased())"
        let photoID = FoundryRuleIdentity.uuid(for: "\(sourceIdentifier)#photo")
        let mapID = FoundryRuleIdentity.uuid(for: "\(sourceIdentifier)#map")
        let provenance = ExternalImportProvenance(
            source: "Universal VTT",
            sourceScopeID: sourceScopeID,
            packageIdentifier: sourceIdentifier,
            sourcePath: sourceURL.lastPathComponent,
            sourceVersion: document.formatVersion.map { String($0) }
        )
        let imageExtension = URL(filePath: document.imageResource.logicalPath).pathExtension
        guard let normalizationPlan = FoundryMediaNormalizer.plan(
            for: "\(sourceName).\(imageExtension)"
        ), normalizationPlan.kind == .image else {
            throw FoundryMediaNormalizationError.invalidImage
        }

        let attachment = ExternalImportAttachment(
            id: photoID,
            fileID: photoID,
            suggestedFilename: normalizationPlan.suggestedFilename,
            contentTypeIdentifier: normalizationPlan.contentTypeIdentifier,
            expectedByteCount: nil,
            contentHash: nil,
            load: {
                let sourceData = try await resourceLoader(document.imageResource)
                return try await normalizationPlan.normalize(sourceData)
            }
        )
        let photo = PhotoModel.empty(photoID)
        photo.name = sourceName
        photo.description = "Map image embedded in \(sourceURL.lastPathComponent)."
        photo.category = .photo
        photo.tags = ["Universal VTT"]

        let pixelsPerGrid = document.resolution.pixelsPerGrid
        let width = max(1, document.resolution.mapSize.x * pixelsPerGrid)
        let height = max(1, document.resolution.mapSize.y * pixelsPerGrid)
        let walls = walls(from: document, sourceIdentifier: sourceIdentifier)
        try Task.checkCancellation()
        let lightDescription = document.lights.isEmpty
            ? ""
            : "\n\n\(document.lights.count.formatted()) light definitions are retained in the normalized source archive."
        let map = MapModel(
            id: mapID,
            name: sourceName,
            description: "Imported Universal VTT map.\(lightDescription)",
            tags: ["Universal VTT"],
            category: .dungeon,
            photoId: photoID,
            width: width,
            height: height,
            walls: walls,
            hexMapScale: pixelsPerGrid
        )

        let photoItem = ExternalImportBatchItem(
            id: photoID,
            module: .photo,
            name: photo.name,
            model: photo,
            provenance: provenance,
            attachment: attachment
        )
        let mapItem = ExternalImportBatchItem(
            id: mapID,
            module: .map,
            name: map.name,
            model: map,
            provenance: provenance,
            warnings: document.lights.isEmpty
                ? []
                : ["Universal VTT lights have no MapRPG runtime equivalent and remain in the raw archive."]
        )
        let warnings = document.lights.isEmpty
            ? []
            : ["Universal VTT light definitions are preserved for a future spatial-light model."]
        let batch = ExternalImportBatch(
            id: FoundryRuleIdentity.uuid(for: "\(sourceIdentifier)#batch"),
            title: sourceName,
            provenance: provenance,
            items: [photoItem, mapItem],
            warnings: warnings
        )
        let package = syntheticPackage(
            document: document,
            sourceName: sourceName,
            sourceIdentifier: sourceIdentifier
        )
        let mappings = [
            FoundryImportMapping(
                foundryIdentifier: "\(sourceIdentifier)#image",
                references: [FoundryImportMappingReference(module: .photo, itemId: photoID)]
            ),
            FoundryImportMapping(
                foundryIdentifier: "\(sourceIdentifier)#scene",
                references: [FoundryImportMappingReference(module: .map, itemId: mapID)]
            )
        ]
        return FoundryMappedImport(
            batch: batch,
            mappings: mappings,
            archiveID: sourceScopeID,
            rawOnlyDocumentCount: document.lights.count,
            missingResources: [],
            unsupportedResources: [],
            archivePackage: package
        )
    }
}

private extension UniversalVTTDomainMapper {
    func walls(from document: UniversalVTTDocument, sourceIdentifier: String) -> [MapWallModel] {
        var result: [MapWallModel] = []
        appendSegments(
            document.lineOfSight,
            kind: "line-of-sight",
            sourceIdentifier: sourceIdentifier,
            resolution: document.resolution,
            to: &result
        )
        appendSegments(
            document.objectsLineOfSight,
            kind: "object-line-of-sight",
            sourceIdentifier: sourceIdentifier,
            resolution: document.resolution,
            to: &result
        )
        for (index, portal) in document.portals.enumerated() {
            let endpoints: (UniversalVTTPoint, UniversalVTTPoint)?
            if portal.bounds.count >= 2, let first = portal.bounds.first, let last = portal.bounds.last {
                endpoints = (first, last)
            } else if let position = portal.position {
                // Universal VTT portal rotation is already expressed in radians.
                let radians = portal.rotation ?? 0
                let halfLength = 0.5
                let dx = cos(radians) * halfLength
                let dy = sin(radians) * halfLength
                endpoints = (
                    UniversalVTTPoint(x: position.x - dx, y: position.y - dy),
                    UniversalVTTPoint(x: position.x + dx, y: position.y + dy)
                )
            } else {
                endpoints = nil
            }
            guard let endpoints else { continue }
            let key = "\(sourceIdentifier)#portal#\(index)"
            result.append(MapWallModel(
                id: FoundryRuleIdentity.uuid(for: key),
                sourceIdentifier: key,
                start: point(endpoints.0, resolution: document.resolution),
                end: point(endpoints.1, resolution: document.resolution),
                movementRestriction: .normal,
                sightRestriction: .normal,
                doorType: .door,
                doorState: portal.isClosed ? .closed : .open,
                rawMetadata: portal.rawData
            ))
        }
        return result
    }

    func appendSegments(
        _ paths: [[UniversalVTTPoint]],
        kind: String,
        sourceIdentifier: String,
        resolution: UniversalVTTResolution,
        to result: inout [MapWallModel]
    ) {
        for (pathIndex, path) in paths.enumerated() where path.count > 1 {
            for segmentIndex in 0..<(path.count - 1) {
                let key = "\(sourceIdentifier)#\(kind)#\(pathIndex)#\(segmentIndex)"
                result.append(MapWallModel(
                    id: FoundryRuleIdentity.uuid(for: key),
                    sourceIdentifier: key,
                    start: point(path[segmentIndex], resolution: resolution),
                    end: point(path[segmentIndex + 1], resolution: resolution),
                    movementRestriction: .normal,
                    sightRestriction: .normal
                ))
            }
        }
    }

    func point(_ point: UniversalVTTPoint, resolution: UniversalVTTResolution) -> CGPoint {
        CGPoint(
            x: (point.x - resolution.mapOrigin.x) * resolution.pixelsPerGrid,
            y: (point.y - resolution.mapOrigin.y) * resolution.pixelsPerGrid
        )
    }

    func syntheticPackage(
        document: UniversalVTTDocument,
        sourceName: String,
        sourceIdentifier: String
    ) -> FoundryVTTImportPackage {
        let scene = FoundryDocument(
            id: "\(sourceIdentifier)#scene",
            documentID: sourceIdentifier,
            documentType: .scene,
            subtype: "UniversalVTT",
            name: sourceName,
            folderID: nil,
            sort: nil,
            imagePath: document.imageResource.logicalPath,
            descriptionHTML: nil,
            parentID: nil,
            embeddedDocuments: [],
            references: [],
            unknownFieldNames: document.rawData.objectValue?.keys.sorted() ?? [],
            rawData: document.rawData
        )
        let collection = FoundryDocumentCollection(
            id: "\(sourceIdentifier)#collection",
            name: sourceName,
            label: "Universal VTT",
            sourcePath: sourceName,
            declaredDocumentType: .scene,
            documents: [scene],
            folders: []
        )
        return FoundryVTTImportPackage(
            sourceSHA256: document.sourceSHA256,
            kind: .exportedDocument,
            manifestPath: nil,
            manifest: nil,
            collections: [collection],
            resources: [document.imageResource],
            diagnostics: [],
            statistics: FoundryVTTImportStatistics(
                collectionCount: 1,
                topLevelDocumentCount: 1,
                embeddedDocumentCount: 0,
                folderCount: 0,
                unknownFieldCount: document.rawData.objectValue?.count ?? 0,
                documentCounts: [FoundryDocumentType.scene.rawValue: 1]
            )
        )
    }

}
