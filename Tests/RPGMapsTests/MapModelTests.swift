// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import Foundation
import Testing

@testable import MapRPG

struct MapModelTests {
    func setUp() async throws -> MapModel {
        MapModel(
            id: UUID(),
            name: "My Name",
            description: "My Desc",
            tags: ["Map"],
            category: .map,
            displayState: 23,
            entries: [MapEntryModel(id: UUID(), name: "Sub", content: "Info", coordinates: [])],
            displayConfig: DisplayConfigModel(id: UUID(), tileCoordinates: [], border: DisplayBorderViewModel(id: UUID())),
            photoId: UUID(),
            width: 100,
            height: 2000,
            mapPins: [MapPinModel(id: UUID(), name: "pin")],
            pinScale: 1.5, scale: 2.0, degrees: -90
        )
    }

    @Test func assignAndDuplicate() async throws {
        let sut = try await setUp()
        let a = sut
        #expect(a == sut)

        let d = sut.duplicate()
        #expect(d.id != a.id)
        #expect(d.name == "\(a.name) Copy")
        #expect(d.description == a.description)
        #expect(d.tags == a.tags)
        #expect(d.category == a.category)
        #expect(d.displayState == a.displayState)
        #expect(d.entries.count == a.entries.count)
        #expect(d.displayConfig == a.displayConfig)
        #expect(d.photoId == a.photoId)
        #expect(d.width == a.width)
        #expect(d.height == a.height)
        #expect(d.mapPins == a.mapPins)
        #expect(d.pinScale == a.pinScale)
        #expect(d.scale == a.scale)
        #expect(d.degrees == a.degrees)
    }

    @Test func changeValues() async throws {
        let sut = try await setUp()
        let a = sut.copy()
        #expect(sut.isSame(a) == true)

        a.name = "Good"
        #expect(sut.isSame(a) == false)

        sut.description = "My Content"
        sut.name = "Better"
        a.description = "Take this"
        a.tags = ["Better"]
        sut.category = .map
        a.resetImage(with: UUID(), size: CGSize(width: 56, height: 100), degrees: 0)
        sut[MapPinId.id, sut.mapPins.first!.id] = MapPinModel(id: UUID(), name: "Hi")
        a.pinScale = 2.0
        a.displayState = 100

        let m1 = a.merge(sut)
        #expect(m1.id == a.id)
        #expect(m1.name == sut.name)
        #expect(m1.description == a.description)
        #expect(m1.tags == a.tags)
        #expect(m1.category == a.category)
        #expect(m1.displayState == sut.displayState)
        #expect(m1.entries == a.entries)
        #expect(m1.displayConfig == a.displayConfig)
        #expect(m1.photoId == a.photoId)
        #expect(m1.width == a.width)
        #expect(m1.height == a.height)
        #expect(m1.mapPins != a.mapPins)
        #expect(m1.pinScale == a.pinScale)
        #expect(m1.scale == sut.scale)
        #expect(m1.degrees == sut.degrees)

        let m2 = sut.merge(a)
        #expect(m2.id == sut.id)
        #expect(m2.name == sut.name)
        #expect(m2.description == a.description)
        #expect(m2.tags == a.tags)
        #expect(m2.category == a.category)
        #expect(m2.displayState == a.displayState)
        #expect(m2.entries == a.entries)
        #expect(m2.displayConfig == a.displayConfig)
        #expect(m2.photoId == a.photoId)
        #expect(m2.width == a.width)
        #expect(m2.height == a.height)
        #expect(m2.mapPins != a.mapPins)
        #expect(m2.pinScale != a.pinScale)
        #expect(m2.scale == a.scale)
        #expect(m2.degrees == a.degrees)

        #expect(sut.isSame(a) == false)
        #expect(m1.isSame(m2) == false)
    }
}
#endif
