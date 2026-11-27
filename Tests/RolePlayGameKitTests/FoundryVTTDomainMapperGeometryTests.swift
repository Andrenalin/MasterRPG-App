// @copyright André Trettin

import CoreRPG
import Foundation
import MapRPG
import Testing

@testable import RolePlayGameKit

@MainActor
@Suite("Foundry VTT projected geometry safety")
struct FoundryVTTDomainMapperGeometryTests {
    @Test("Unsafe token and wall geometry stays raw and cannot poison a map projection")
    func omitsUnsafeEmbeddedGeometry() async throws {
        // Given
        let validToken = document(
            id: "scene.Token.valid",
            type: .token,
            rawData: .object([
                "name": .string("Valid token"),
                "x": .integer(10),
                "y": .integer(20),
                "width": .integer(1),
                "height": .integer(2),
            ])
        )
        let overflowingToken = document(
            id: "scene.Token.overflow",
            type: .token,
            rawData: .object([
                "name": .string("Overflowing token"),
                "x": .integer(0),
                "y": .integer(0),
                "width": .integer(1_000_000),
                "height": .integer(1),
            ])
        )
        let validWall = document(
            id: "scene.Wall.valid",
            type: .wall,
            rawData: .object([
                "name": .string("Valid wall"),
                "c": .array([.integer(0), .integer(0), .integer(100), .integer(100)]),
            ])
        )
        let outOfRangeWall = document(
            id: "scene.Wall.coordinate-overflow",
            type: .wall,
            rawData: .object([
                "name": .string("Out-of-range wall"),
                "c": .array([.integer(0), .integer(0), .number(1e308), .integer(100)]),
            ])
        )
        let unsafeRestrictionWall = document(
            id: "scene.Wall.integer-overflow",
            type: .wall,
            rawData: .object([
                "name": .string("Unsafe restriction wall"),
                "c": .array([.integer(0), .integer(0), .integer(100), .integer(100)]),
                "move": .number(1e308),
            ])
        )
        let scene = document(
            id: "Scene.geometry",
            type: .scene,
            rawData: .object([
                "name": .string("Geometry"),
                "width": .integer(1_200),
                "height": .integer(800),
                "grid": .object(["size": .integer(100)]),
            ]),
            embeddedDocuments: [
                validToken,
                overflowingToken,
                validWall,
                outOfRangeWall,
                unsafeRestrictionWall,
            ]
        )

        // When
        let mapped = try await map(scene)
        let map = try #require(mapped.batch.items.compactMap { $0.model as? MapModel }.first)

        // Then
        #expect(map.mapPins.map(\.name) == ["Valid token"])
        #expect(map.mapPins.allSatisfy { pin in
            pin.location.x.isFinite
                && pin.location.y.isFinite
                && abs(pin.location.x) <= FoundryProjectionGeometry.maximumMagnitude
                && abs(pin.location.y) <= FoundryProjectionGeometry.maximumMagnitude
        })
        #expect(map.walls.map(\.sourceIdentifier) == ["scene.Wall.valid"])
        #expect(mapped.rawOnlyDocumentCount == 3)
        let archivedIDs = Set(mapped.archivePackage.allDocuments.map(\.id))
        #expect(archivedIDs.contains(overflowingToken.id))
        #expect(archivedIDs.contains(outOfRangeWall.id))
        #expect(archivedIDs.contains(unsafeRestrictionWall.id))
        #expect(mapped.batch.warnings.contains { $0.contains("tokens had invalid") })
        #expect(mapped.batch.warnings.filter { $0.contains("walls had invalid") }.count == 1)
    }

    @Test("Out-of-range scene dimensions skip the projection but preserve the scene")
    func omitsUnsafeSceneGeometry() async throws {
        // Given
        let scene = document(
            id: "Scene.unsafe",
            type: .scene,
            rawData: .object([
                "name": .string("Unsafe scene"),
                "width": .number(1e308),
                "height": .integer(800),
                "grid": .object(["size": .integer(100)]),
            ])
        )

        // When
        let mapped = try await map(scene)

        // Then
        #expect(mapped.batch.items.allSatisfy { $0.module != .map })
        #expect(mapped.rawOnlyDocumentCount == 1)
        #expect(mapped.archivePackage.allDocuments.contains { $0.id == scene.id })
        #expect(mapped.batch.warnings.contains { $0.contains("scenes had invalid") })
    }

    @Test("Restriction conversion accepts only exactly representable Int values")
    func exactRestrictionIntegerConversion() {
        // Given / When / Then
        #expect(FoundryProjectionGeometry.exactInteger(.integer(20), defaultValue: 0) == 20)
        #expect(FoundryProjectionGeometry.exactInteger(nil, defaultValue: 20) == 20)
        #expect(FoundryProjectionGeometry.exactInteger(.number(20.5), defaultValue: 0) == nil)
        #expect(FoundryProjectionGeometry.exactInteger(.number(1e308), defaultValue: 0) == nil)
        #expect(FoundryProjectionGeometry.exactInteger(.unsignedInteger(.max), defaultValue: 0) == nil)
    }
}

private extension FoundryVTTDomainMapperGeometryTests {
    func map(_ scene: FoundryDocument) async throws -> FoundryMappedImport {
        let sourceScopeId = try #require(
            UUID(uuidString: "D19ACEDC-1D50-4E9B-8982-48D79DE52430")
        )
        let package = FoundryVTTImportPackage(
            kind: .world,
            manifestPath: nil,
            manifest: nil,
            collections: [FoundryDocumentCollection(
                id: "scenes",
                name: "scenes",
                label: "Scenes",
                sourcePath: "data/scenes",
                declaredDocumentType: .scene,
                documents: [scene],
                folders: []
            )],
            resources: [],
            diagnostics: [],
            statistics: FoundryVTTImportStatistics(
                collectionCount: 1,
                topLevelDocumentCount: 1,
                embeddedDocumentCount: scene.embeddedDocuments.count,
                folderCount: 0,
                unknownFieldCount: 0,
                documentCounts: [FoundryDocumentType.scene.rawValue: 1]
            )
        )
        return try await FoundryVTTDomainMapper().map(
            package: package,
            sourceUrl: URL(filePath: "/tmp/foundry-geometry-test.json"),
            sourceScopeId: sourceScopeId,
            selectedCategories: [.scenes],
            resourceLoader: { _ in Data() }
        )
    }

    func document(
        id: String,
        type: FoundryDocumentType,
        rawData: FoundryJSONValue,
        embeddedDocuments: [FoundryDocument] = []
    ) -> FoundryDocument {
        FoundryDocument(
            id: id,
            documentId: id,
            documentType: type,
            subtype: nil,
            name: rawData["name"]?.stringValue ?? id,
            folderId: nil,
            sort: nil,
            imagePath: nil,
            descriptionHTML: nil,
            parentId: nil,
            embeddedDocuments: embeddedDocuments,
            references: [],
            unknownFieldNames: [],
            rawData: rawData
        )
    }
}
