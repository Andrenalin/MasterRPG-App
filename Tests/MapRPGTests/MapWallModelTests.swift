// @copyright André Trettin

#if canImport(Testing)
import CoreGraphics
import CoreRPG
import Foundation
import Testing

@testable import MapRPG

@MainActor
struct MapWallModelTests {
    @Test func deterministicIdentityAndUnknownValuesRoundTrip() throws {
        let sourceIdentifier = "world:my-world:scene:lower-level:wall:door-7"
        let wall = MapWallModel(
            sourceIdentifier: sourceIdentifier,
            start: CGPoint(x: 10.5, y: 20.25),
            end: CGPoint(x: 30.75, y: 40.125),
            movementRestriction: .init(rawValue: 999),
            sightRestriction: .proximity,
            doorType: .secret,
            doorState: .locked,
            minimumElevation: -10,
            maximumElevation: 30,
            levelIdentifier: "lower-level",
            rawMetadata: .object([
                "sound": .integer(20),
                "flags": .object(["wall-height": .bool(true)])
            ])
        )

        #expect(wall.id == MapWallModel.deterministicID(for: sourceIdentifier))
        #expect(wall.id == MapWallModel(sourceIdentifier: sourceIdentifier, start: .zero, end: .zero).id)
        #expect(wall.id != MapWallModel.deterministicID(for: "\(sourceIdentifier)-other"))

        let data = try JSONEncoder().encode(wall)
        let decoded = try JSONDecoder().decode(MapWallModel.self, from: data)

        #expect(decoded == wall)
        #expect(decoded.movementRestriction.rawValue == 999)
    }

    @Test func persistencePayloadIsVersionedAndReadsLegacyRepresentations() throws {
        let wall = makeWall(sourceIdentifier: "scene:one:wall:one")
        let walls = CRDTDataUpdate(wrappedValue: [wall])
        let encoded = try #require(MapWallPersistenceCodec.encode(walls))
        let object = try #require(JSONSerialization.jsonObject(with: Data(encoded.utf8)) as? [String: Any])

        #expect(object["formatVersion"] as? Int == PersistedMapWalls.currentFormatVersion)
        #expect(MapWallPersistenceCodec.decode(encoded) == walls)

        let legacyArrayData = try JSONEncoder().encode([wall])
        let legacyArrayText = try #require(String(data: legacyArrayData, encoding: .utf8))
        #expect(MapWallPersistenceCodec.decode(legacyArrayText).wrappedValue == [wall])
        #expect(MapWallPersistenceCodec.decode(nil).wrappedValue.isEmpty)
        #expect(MapWallPersistenceCodec.decode("not-json").wrappedValue.isEmpty)
    }

    @Test func mapModelCopiesMergesDuplicatesAndCodableIncludesWalls() throws {
        let originalWall = makeWall(sourceIdentifier: "scene:one:wall:original")
        let replacementWall = makeWall(sourceIdentifier: "scene:one:wall:replacement")
        let map = MapModel(id: UUID(), name: "Map", walls: [originalWall])
        let copy = map.copy()
        let originalContentVersion = MapUpdatePayload(model: map).contentVersion

        #expect(copy.walls == [originalWall])
        #expect(map.isSame(copy))

        copy.walls = [replacementWall]
        #expect(!map.isSame(copy))
        #expect(map.merge(copy).walls == [replacementWall])
        #expect(map.duplicate().walls == [originalWall])
        map.walls = [replacementWall]
        #expect(MapUpdatePayload(model: map).contentVersion != originalContentVersion)

        let encoded = try JSONEncoder().encode(map)
        let decoded = try JSONDecoder().decode(MapModel.self, from: encoded)
        #expect(decoded.walls == [replacementWall])
    }

    @Test func mapAndLiveSnapshotDecodePayloadsWithoutWalls() throws {
        let wall = makeWall(sourceIdentifier: "scene:legacy:wall:one")
        let map = MapModel(id: UUID(), name: "Legacy", walls: [wall])

        let mapData = try JSONEncoder().encode(map)
        var mapObject = try #require(JSONSerialization.jsonObject(with: mapData) as? [String: Any])
        #expect(mapObject.removeValue(forKey: "_walls_") != nil)
        let legacyMapData = try JSONSerialization.data(withJSONObject: mapObject)
        let decodedMap = try JSONDecoder().decode(MapModel.self, from: legacyMapData)
        #expect(decodedMap.walls.isEmpty)

        let snapshotData = try JSONEncoder().encode(MapSnapshot(map))
        var snapshotObject = try #require(JSONSerialization.jsonObject(with: snapshotData) as? [String: Any])
        #expect(snapshotObject.removeValue(forKey: "walls") != nil)
        let legacySnapshotData = try JSONSerialization.data(withJSONObject: snapshotObject)
        let decodedSnapshot = try JSONDecoder().decode(MapSnapshot.self, from: legacySnapshotData)
        #expect(decodedSnapshot.walls.wrappedValue.isEmpty)
    }

    @Test func resizingMapScalesWallEndpoints() throws {
        let wall = MapWallModel(
            sourceIdentifier: "scene:scale:wall:one",
            start: CGPoint(x: 10, y: 20),
            end: CGPoint(x: 30, y: 40)
        )
        let map = MapModel(
            id: UUID(),
            name: "Rotated map",
            width: 100,
            height: 50,
            walls: [wall]
        )

        map.resetImage(
            with: UUID(),
            size: CGSize(width: 200, height: 100),
            degrees: 90
        )

        let resizedWall = try #require(map.walls.first)
        #expect(resizedWall.start == CGPoint(x: 10, y: 80))
        #expect(resizedWall.end == CGPoint(x: 30, y: 160))
    }

    private func makeWall(sourceIdentifier: String) -> MapWallModel {
        MapWallModel(
            sourceIdentifier: sourceIdentifier,
            start: CGPoint(x: 1, y: 2),
            end: CGPoint(x: 3, y: 4),
            movementRestriction: .normal,
            sightRestriction: .limited,
            doorType: .door,
            doorState: .closed
        )
    }
}
#endif
