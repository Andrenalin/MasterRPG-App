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
