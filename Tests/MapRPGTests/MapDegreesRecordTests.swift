// @copyright André Trettin

#if canImport(Testing)
import CoreGraphics
import CoreRPG
import Foundation
import PhotoRPG
import Testing

#if os(macOS)
import AppKit
#else
import UIKit
#endif

@testable import MapRPG

/// Validate Folders moved the rooms and pins of a rotated map by another 90° on every run: the
/// map's rotation was never stored, so each launch started at 0° and the repair turned the content
/// from 0° to the photo's rotation again. `hasRecordedDegrees` marks a map whose rotation is
/// unknown; the repair adopts the photo's rotation for it without moving content.
@MainActor
@Suite("Map rotation record")
struct MapDegreesRecordTests {
    private let photoId = UUID()
    private let imageSize = CGSize(width: 100, height: 50)

    /// A map saved before the rotation was persisted: its content already follows a photo turned
    /// by 90°, so the canvas is 50 × 100, while the loaded `degrees` is the placeholder 0.
    private func legacyRotatedMap() -> MapModel {
        let map = MapModel(
            id: UUID(),
            name: "Legacy",
            entries: [MapEntryModel(id: UUID(), name: "Room", content: "", coordinates: [CGPoint(x: 40, y: 20), CGPoint(x: 10, y: 80)])],
            photoId: photoId,
            width: 50,
            height: 100,
            mapPins: [MapPinModel(id: UUID(), name: "Pin", location: CGPoint(x: 30, y: 70))],
            degrees: 0,
            hasRecordedDegrees: false
        )
        return map
    }

    /// What `EditController.resetImageSize(save: true)` does to the map.
    private func repair(_ map: MapModel, photoDegrees: Double) {
        map.recordLegacyDegrees(photoDegrees)
        map.resetImage(with: photoId, size: imageSize, degrees: photoDegrees)
    }

    // MARK: - Repair flow

    @Test("A legacy rotated map adopts the photo's rotation and keeps its rooms and pins")
    func legacyMapKeepsContent() {
        let map = legacyRotatedMap()

        repair(map, photoDegrees: 90)

        #expect(map.degrees == 90)
        #expect(map.hasRecordedDegrees)
        #expect(map.width == 50)
        #expect(map.height == 100)
        #expect(map.entries.first?.coordinates == [CGPoint(x: 40, y: 20), CGPoint(x: 10, y: 80)])
        #expect(map.mapPins.first?.location == CGPoint(x: 30, y: 70))
    }

    @Test("Without the record the unrecorded 0 is taken as the old rotation and the content turns again")
    func unrecordedZeroWouldTurnTheContent() {
        let map = legacyRotatedMap()

        map.resetImage(with: photoId, size: imageSize, degrees: 90)

        #expect(map.entries.first?.coordinates != [CGPoint(x: 40, y: 20), CGPoint(x: 10, y: 80)],
                "this is the bug the record prevents")
    }

    @Test("Repairing again changes nothing")
    func repairIsIdempotent() {
        let map = legacyRotatedMap()
        repair(map, photoDegrees: 90)
        let afterFirst = map.copy()

        repair(map, photoDegrees: 90)

        #expect(map.isSame(afterFirst))
        #expect(map.entries.first?.coordinates == afterFirst.entries.first?.coordinates)
    }

    @Test("A map at 0° is recorded without any content change")
    func unrotatedLegacyMapIsOnlyRecorded() {
        let map = MapModel(
            id: UUID(), name: "Flat",
            entries: [MapEntryModel(id: UUID(), name: "Room", content: "", coordinates: [CGPoint(x: 20, y: 10)])],
            photoId: photoId, width: 100, height: 50, degrees: 0, hasRecordedDegrees: false
        )
        let before = map.entries

        repair(map, photoDegrees: 0)

        #expect(map.hasRecordedDegrees)
        #expect(map.degrees == 0)
        #expect(map.entries == before)
    }

    @Test("A legacy map still follows a photo whose shape differs, using the adopted rotation")
    func legacyMapWithChangedPhotoSizeIsScaled() {
        let map = legacyRotatedMap()

        map.recordLegacyDegrees(90)
        map.resetImage(with: photoId, size: CGSize(width: 200, height: 100), degrees: 90)

        #expect(map.width == 100)
        #expect(map.height == 200)
        #expect(map.entries.first?.coordinates == [CGPoint(x: 80, y: 40), CGPoint(x: 20, y: 160)])
    }

    @Test("A recorded rotation is never replaced by the legacy adoption")
    func recordedRotationWins() {
        let map = MapModel(id: UUID(), name: "Recorded", width: 50, height: 100, degrees: 90)

        map.recordLegacyDegrees(0)

        #expect(map.degrees == 90)
        #expect(map.hasRecordedDegrees)
    }

    @Test("A recorded map still adapts its content when the photo's rotation really changes")
    func recordedMapAdaptsToRotationChange() {
        let map = MapModel(
            id: UUID(), name: "Recorded",
            entries: [MapEntryModel(id: UUID(), name: "Room", content: "", coordinates: [CGPoint(x: 20, y: 10)])],
            photoId: photoId, width: 100, height: 50, degrees: 0
        )

        repair(map, photoDegrees: 90)

        #expect(map.degrees == 90)
        #expect(map.entries.first?.coordinates == [CGPoint(x: 40, y: 20)])
    }

    @Test("Replacing the photo records the rotation")
    func resetImageRecords() {
        let map = MapModel(id: UUID(), name: "Map", photoId: photoId, width: 100, height: 50, degrees: 0, hasRecordedDegrees: false)

        map.resetImage(with: photoId, size: imageSize, degrees: 0)

        #expect(map.hasRecordedDegrees)
    }

    @Test("New maps start with a recorded rotation")
    func newMapIsRecorded() {
        #expect(MapModel(id: UUID(), name: "New").hasRecordedDegrees)
        #expect(MapModel.empty.hasRecordedDegrees)
    }

    // MARK: - Model plumbing

    @Test("The record takes part in equality, copy, replace and duplicate")
    func recordIsPartOfTheModel() {
        let recorded = MapModel(id: UUID(), name: "Map", degrees: 90)
        let unrecorded = recorded.copy()
        unrecorded.hasRecordedDegrees = false

        #expect(!recorded.isSame(unrecorded), "the flag alone must count as a change, or the repair is never saved")
        #expect(recorded != unrecorded)
        #expect(unrecorded.copy().hasRecordedDegrees == false)

        #expect(recorded.replace(with: unrecorded))
        #expect(recorded.hasRecordedDegrees == false)
    }

    @Test("An unrecorded rotation never overrides a recorded one in a merge")
    func mergeKeepsTheRecordedRotation() {
        let recorded = MapModel(id: UUID(), name: "Map", degrees: 90)
        let unrecorded = recorded.copy()
        unrecorded.degrees = 0
        unrecorded.hasRecordedDegrees = false

        let mergedIntoRecorded = recorded.merge(unrecorded)
        #expect(mergedIntoRecorded.degrees == 90)
        #expect(mergedIntoRecorded.hasRecordedDegrees)

        let mergedIntoUnrecorded = unrecorded.merge(recorded)
        #expect(mergedIntoUnrecorded.degrees == 90)
        #expect(mergedIntoUnrecorded.hasRecordedDegrees)

        let bothUnrecorded = unrecorded.merge(unrecorded.copy())
        #expect(!bothUnrecorded.hasRecordedDegrees)
    }

    // MARK: - Wire format

    @Test("The record survives the .gmz wire format")
    func modelRoundTrip() throws {
        for recorded in [true, false] {
            let map = MapModel(id: UUID(), name: "Map", degrees: recorded ? 90 : 0, hasRecordedDegrees: recorded)

            let data = try JSONEncoder().encode(map)
            let decoded = try JSONDecoder().decode(MapModel.self, from: data)

            #expect(decoded.hasRecordedDegrees == recorded)
            #expect(decoded.degrees == map.degrees)
        }
    }

    @Test("A map from a sender that predates the record decodes as unrecorded")
    func modelFromOldSenderIsUnrecorded() throws {
        let map = MapModel(id: UUID(), name: "Map", degrees: 0)
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(map)) as? [String: Any])
        #expect(object.removeValue(forKey: "_hasRecordedDegrees") != nil)

        let decoded = try JSONDecoder().decode(MapModel.self, from: JSONSerialization.data(withJSONObject: object))

        #expect(!decoded.hasRecordedDegrees)
    }

    @Test("The snapshot carries the record across the persistence boundary and the wire")
    func snapshotRoundTrip() throws {
        for recorded in [true, false] {
            let map = MapModel(id: UUID(), name: "Map", degrees: recorded ? 90 : 0, hasRecordedDegrees: recorded)
            let snapshot = MapSnapshot(map)

            #expect(snapshot.hasRecordedDegrees == recorded)
            #expect(snapshot.makeModel().hasRecordedDegrees == recorded)
            #expect(snapshot.redactedForNonMaster().hasRecordedDegrees == recorded)

            let decoded = try JSONDecoder().decode(MapSnapshot.self, from: JSONEncoder().encode(snapshot))
            #expect(decoded.hasRecordedDegrees == recorded)

            let target = MapModel(id: map.id, name: "Other", degrees: 45, hasRecordedDegrees: !recorded)
            snapshot.apply(to: target)
            #expect(target.hasRecordedDegrees == recorded)
            #expect(target.degrees == map.degrees)
        }
    }

    @Test("A snapshot from a sender that predates the record decodes as unrecorded")
    func snapshotFromOldSenderIsUnrecorded() throws {
        let snapshot = MapSnapshot(MapModel(id: UUID(), name: "Map", degrees: 0))
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as? [String: Any])
        #expect(object.removeValue(forKey: "hasRecordedDegrees") != nil)

        let decoded = try JSONDecoder().decode(MapSnapshot.self, from: JSONSerialization.data(withJSONObject: object))

        #expect(!decoded.hasRecordedDegrees)
    }

    // MARK: - Repair on the real root

    @Test("The photo geometry from the header is what the decoded photo reports")
    func photoGeometryMatchesTheDecodedPhoto() async throws {
        let root = try await MockRoot.importTestData()
        let itemId = try #require(root.itemController.itemDataModel.items.first)
        let mapPhotoId = try #require(root.itemController.itemOrEmpty(for: itemId).photoId)
        let (image, degrees) = try #require(await root.photoRoot.fetchPhotoImage(for: mapPhotoId, useGame: false))

        let geometry = try #require(await root.photoRoot.fetchPhotoGeometry(for: mapPhotoId, useGame: false))

        #expect(geometry.size == image.size)
        #expect(geometry.degrees == degrees)
        #expect(await root.photoRoot.fetchPhotoGeometry(for: nil, useGame: false) == nil)
    }

    @Test("Validating an imported map twice moves nothing the second time and keeps the rotation recorded")
    func repairOnRootIsStable() async throws {
        let root = try await MockRoot.importTestData()
        let itemId = try #require(root.itemController.itemDataModel.items.first)
        let map = root.itemController.itemOrEmpty(for: itemId)
        let mapPhotoId = try #require(map.photoId)
        try #require(await root.photoRoot.fetchPhotoImage(for: mapPhotoId, useGame: false) != nil, "the test map needs its photo")

        // A .gmz from before the record decodes as unrecorded, like a map loaded from an old store.
        map.hasRecordedDegrees = false
        map.degrees = 0
        root.itemController.replace(model: map, isInsert: false)

        await root.editController.resetImageSize(photoId: mapPhotoId, updateModel: map, save: true)
        let afterFirst = root.itemController.itemOrEmpty(for: itemId).copy()
        #expect(afterFirst.hasRecordedDegrees)

        await root.editController.resetImageSize(photoId: mapPhotoId, updateModel: afterFirst, save: true)
        let afterSecond = root.itemController.itemOrEmpty(for: itemId)

        #expect(afterSecond.isSame(afterFirst))
        #expect(afterSecond.entries.map(\.coordinates) == afterFirst.entries.map(\.coordinates))
        #expect(afterSecond.degrees == afterFirst.degrees)
    }
}
#endif
