// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import Foundation
import Testing

@testable import MapRPG

@MainActor
struct MapEntryModelTests {
    func setUp() async throws -> MapEntryModel {
        MapEntryModel(
            id: UUID(),
            name: "My Name",
            content: "My Descr",
            coordinates: [CGPoint(x: 1, y: 2)],
            isShown: true,
            focused: true,
            displayState: 3
        )
    }

    @Test func assignAndDuplicate() async throws {
        let sut = try await setUp()
        let a = sut
        #expect(a == sut)

        let d = sut.duplicate()
        #expect(d.id != a.id)
        #expect(d.name == a.name)
        #expect(d.content == a.content)
        #expect(d.coordinates == a.coordinates)
        #expect(d.isShown == a.isShown)
        #expect(d.focused == a.focused)
        #expect(d.displayState == a.displayState)
    }

    @Test func ChangeValues() async throws {
        var sut = try await setUp()
        var a = sut
        #expect(sut.isSame(a) == true)

        a.name = "Good"
        #expect(sut.isSame(a) == false)

        sut.content = "My Content"
        sut.name = "Better"
        a.content = "Take this"
        sut.coordinates = [CGPoint(x: 2, y: 4), CGPoint(x: 0, y: 8)]
        sut.isShown = false
        a.isShown = false
        a.displayState = 100

        let m1 = a.merge(sut)
        #expect(m1.id == a.id)
        #expect(m1.name == sut.name)
        #expect(m1.content == a.content)
        #expect(m1.coordinates == sut.coordinates)
        #expect(m1.isShown == sut.isShown)
        #expect(m1.focused != sut.focused)
        #expect(m1.displayState != sut.displayState)

        let m2 = sut.merge(a)
        #expect(m2.id == sut.id)
        #expect(m2.name == sut.name)
        #expect(m2.content == a.content)
        #expect(m2.coordinates == sut.coordinates)
        #expect(m2.isShown == a.isShown)
        #expect(m2.focused != a.focused)
        #expect(m2.displayState != a.displayState)

        #expect(sut.isSame(a) == false)
        #expect(m1.isSame(m2) == true)
    }

    @Test func mapSpecificDifferencesAreDetected() {
        // Given
        let existing = MapEntryModel.fixture(
            id: .fixture1,
            name: "Shared name",
            content: "Shared content",
            coordinates: [CGPoint(x: 0, y: 0)],
            isHexGrid: false,
            isShown: false
        )
        var coordinatesChanged = existing
        coordinatesChanged.coordinates = [CGPoint(x: 1, y: 0)]
        var hexGridChanged = existing
        hexGridChanged.isHexGrid = true
        var visibilityChanged = existing
        visibilityChanged.isShown = true

        // When / Then
        for changed in [coordinatesChanged, hexGridChanged, visibilityChanged] {
            #expect(existing.name == changed.name)
            #expect(existing.content == changed.content)
            #expect(!existing.isSame(changed))
        }
    }
}
#endif
