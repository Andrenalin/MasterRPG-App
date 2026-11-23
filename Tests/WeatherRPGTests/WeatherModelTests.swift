// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import Foundation
import Testing
@testable import WeatherRPG

@MainActor
struct WeatherModelTests {
    func setUp() async throws -> WeatherModel {
        WeatherModel(
            id: UUID(),
            name: "Hello",
            description: "Nice",
            tags: ["Stromy"],
            time: 100,
            cloudThickness: .none,
            stormType: .rain,
            rainAngle: 90.0,
            rainIntensity: 12.0,
            lightningFrequency: 50.0,
            lightningMaxBolts: 23.0,
            lightningForkProbability: 99.0,
            photoId: nil
        )
    }

    @Test func assignAndDuplicate() async throws {
        let sut = try await setUp()
        let a = sut
        #expect(a == sut)

        let d = sut.duplicate()
        #expect(d.id != a.id)
        #expect(d.name == "\(a.name) Copy")
    }

    @Test func changeValues() async throws {
        let sut = try await setUp()
        let a = sut
        a.name = "Supert"
        #expect(a.name == "Supert")

        let m1 = sut.merge(a)
        #expect(m1.id == a.id)
        #expect(m1.name == a.name)

        let m2 = a.merge(sut)
        #expect(sut.isSame(a) == true)
        #expect(m1.isSame(m2) == true)
    }

    // CODE_AUDIT_26 §5.42
    @Test func renamingDoesNotMoveTheWeatherStamp() async throws {
        let sut = try await setUp()
        let incoming = sut.duplicate()
        incoming.name = "Renamed"
        let stamp = sut.weatherUpdate_.wrappedValue

        let changed = sut.replace(with: incoming)

        #expect(changed)
        #expect(sut.name == "Renamed")
        #expect(sut.weatherUpdate_.wrappedValue == stamp)
    }

    // CODE_AUDIT_28 §5.8: the photo is merged by the weather stamp, which a photo edit never moved.
    @Test func linkingAPhotoWinsTheMergeOverADeviceThatKeptNoPhoto() async throws {
        let device = try await setUp()
        let other = device.duplicate()
        let edited = device.copy()
        let photoId = UUID()
        let incoming = edited.copy()
        incoming.photoId = photoId
        _ = edited.replace(with: incoming)

        let merged = other.merge(edited)
        #expect(merged.photoId == photoId)
        // The device that kept its value merges the other way round, too.
        #expect(edited.merge(other).photoId == photoId)

        let removal = edited.copy()
        removal.photoId = nil
        _ = edited.replace(with: removal)
        #expect(merged.merge(edited).photoId == nil)
    }

    @Test func changingAWeatherValueMovesTheWeatherStamp() async throws {
        let sut = try await setUp()
        let incoming = sut.duplicate()
        incoming.rainIntensity = 80.0
        let stamp = sut.weatherUpdate_.wrappedValue

        let changed = sut.replace(with: incoming)

        #expect(changed)
        #expect(sut.rainIntensity == 80.0)
        #expect(sut.weatherUpdate_.wrappedValue != stamp)
    }
}
#endif
