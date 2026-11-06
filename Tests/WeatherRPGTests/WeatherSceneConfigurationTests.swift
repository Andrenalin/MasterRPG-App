// @copyright André Trettin

#if os(iOS) || os(macOS) || os(visionOS)
import Foundation
import RealityKit
import Testing

@testable import WeatherRPG

/// The 3D weather on the game table: how a weather maps to its rain or snow, clouds, stars and
/// lightning, and how the entities follow.
@Suite("3D table weather")
@MainActor
struct WeatherSceneConfigurationTests {
    private static let midnight = 0.0
    private static let noon = 0.5

    private static func configuration(
        time: Double = noon,
        clouds: Cloud.Thickness = .regular,
        storm: Storm.Contents = .rain,
        rainAngle: Double = 0,
        intensity: Double = 500,
        lightning: Double = 0,
        bolts: Double = 4,
        fork: Double = 20,
        reduceMotion: Bool = false,
        dimFlashingLights: Bool = false
    ) -> WeatherSceneConfiguration {
        WeatherSceneConfiguration(
            time: time,
            cloudThickness: clouds,
            stormType: storm,
            rainAngle: rainAngle,
            rainIntensity: intensity,
            lightningFrequency: lightning,
            lightningMaxBolts: bolts,
            lightningForkProbability: fork,
            reduceMotion: reduceMotion,
            dimFlashingLights: dimFlashingLights
        )
    }

    private static let volume = WeatherVolume(width: 1, depth: 1.5, floorY: 0, height: 0.5)

    // MARK: - Configuration

    @Test("Without a storm nothing falls; more intensity makes more drops")
    func precipitation() {
        let dry = Self.configuration(storm: .none)
        #expect(dry.precipitation == .none)
        #expect(dry.precipitationCount == 0)

        let light = Self.configuration(intensity: 100)
        let heavy = Self.configuration(intensity: 800)
        #expect(light.precipitation == .rain)
        #expect(light.precipitationCount > 0)
        #expect(heavy.precipitationCount > light.precipitationCount)

        let snow = Self.configuration(storm: .snow)
        #expect(snow.precipitation == .snow)
        #expect(snow.fallSpeed < light.fallSpeed)
    }

    @Test("The wind leans the fall the way the 2D rain angle does, and out-of-range angles are clamped")
    func wind() {
        #expect(Self.configuration(rainAngle: 0).windTilt == 0)
        #expect(Self.configuration(rainAngle: 45).windTilt > 0)
        #expect(Self.configuration(rainAngle: -45).windTilt < 0)
        #expect(Self.configuration(rainAngle: 1_000).windTilt == Self.configuration(rainAngle: 90).windTilt)
    }

    @Test("Stars shine at night only; thicker clouds mean more clouds")
    func starsAndClouds() {
        #expect(Self.configuration(time: Self.midnight).starOpacity > 0.9)
        #expect(Self.configuration(time: Self.noon).starOpacity < WeatherSceneConfiguration.visibleOpacity)

        #expect(Self.configuration(clouds: .none).cloudCount == 0)
        #expect(Self.configuration(clouds: .none).cloudOpacity == 0)
        #expect(Self.configuration(clouds: .ultra).cloudCount > Self.configuration(clouds: .thin).cloudCount)
        #expect(Self.configuration(clouds: .ultra).cloudOpacity > Self.configuration(clouds: .thin).cloudOpacity)
    }

    @Test("Lightning strikes only from one strike a minute on, with bolts")
    func lightning() throws {
        #expect(Self.configuration(lightning: 0).lightning == nil)
        #expect(Self.configuration(lightning: 0.5).lightning == nil)
        #expect(Self.configuration(lightning: 10, bolts: 0).lightning == nil)

        let storm = try #require(Self.configuration(lightning: 10, bolts: 3, fork: 50).lightning)
        #expect(storm.strikesPerMinute == 10)
        #expect(storm.maximumBolts == 3)
        #expect(storm.forkProbability == 0.5)
    }

    @Test("Reduce Motion stops the rain and lightning; Dim Flashing Lights stops only the lightning")
    func accessibility() {
        let still = Self.configuration(lightning: 10, reduceMotion: true)
        #expect(!still.isAnimated)
        #expect(still.precipitationCount == 0)
        #expect(still.lightning == nil)
        #expect(still.cloudCount > 0)

        let dimmed = Self.configuration(lightning: 10, dimFlashingLights: true)
        #expect(dimmed.isAnimated)
        #expect(dimmed.precipitationCount > 0)
        #expect(dimmed.lightning == nil)
    }

    // MARK: - Lightning path

    @Test("A bolt runs from the clouds down to the floor; forks never exceed the maximum")
    func boltPath() throws {
        var generator = SeededGenerator(seed: 7)
        let single = LightningBoltPath.strike(in: Self.volume, maximumBolts: 4, forkProbability: 0, using: &generator)
        let main = try #require(single.first)
        #expect(single.count == 1)
        #expect(main.points.first?.y == Self.volume.floorY + Self.volume.height * LightningBoltPath.cloudLayer)
        #expect(main.points.last?.y == Self.volume.floorY)

        let forked = LightningBoltPath.strike(in: Self.volume, maximumBolts: 3, forkProbability: 1, using: &generator)
        #expect(forked.count == 3)
        #expect(forked.dropFirst().allSatisfy { $0.thickness < 1 })
        #expect(forked.allSatisfy { bolt in bolt.points.allSatisfy { $0.y >= Self.volume.floorY } })
    }

    // MARK: - Entities

    @Test("A night storm shows rain, clouds, stars and lightning; the same weather again keeps them")
    func effectBuildsAndKeeps() async throws {
        let effect = WeatherTableEffect()
        let storm = Self.configuration(time: Self.midnight, lightning: 10)
        effect.show(storm, in: Self.volume)
        // The particle textures load off the main actor the first time.
        await effect.waitForBuild()

        let names = Set(effect.entity.children.map(\.name))
        #expect(names == [
            WeatherTableEffect.precipitationName,
            WeatherTableEffect.cloudsName,
            WeatherTableEffect.starsName,
            WeatherTableEffect.lightningName,
        ])
        let rain = try #require(effect.entity.findEntity(named: WeatherTableEffect.precipitationName))
        #expect(rain.components[ParticleEmitterComponent.self] != nil)

        // A map sync shows the same weather again: the falling rain is not restarted.
        effect.show(storm, in: Self.volume)
        #expect(effect.entity.findEntity(named: WeatherTableEffect.precipitationName) === rain)

        // A larger map rebuilds the weather over it.
        effect.show(storm, in: WeatherVolume(width: 1.2, depth: 1.5, floorY: 0, height: 0.5))
        #expect(effect.entity.findEntity(named: WeatherTableEffect.precipitationName) !== rain)

        effect.hide()
        #expect(effect.entity.children.isEmpty)
        #expect(effect.configuration == nil)
    }

    @Test("A clear day shows only its clouds; a table without room for clouds shows none")
    func effectLeavesOutWhatIsNotThere() async {
        let effect = WeatherTableEffect()
        effect.show(Self.configuration(time: Self.noon, storm: .none), in: Self.volume)
        await effect.waitForBuild()
        #expect(effect.entity.children.map(\.name) == [WeatherTableEffect.cloudsName])

        effect.show(
            Self.configuration(time: Self.noon, storm: .none),
            in: WeatherVolume(width: 1, depth: 1.5, floorY: 0, height: 0.5, cloudOpacityLimit: 0)
        )
        #expect(effect.entity.children.isEmpty)
        #expect(effect.configuration != nil)
    }

    @Test("A weather removed while its textures load is never built")
    func effectRemovedWhileLoading() async {
        let effect = WeatherTableEffect()
        effect.show(Self.configuration(time: Self.noon, storm: .none), in: Self.volume)
        effect.hide()
        await effect.waitForBuild()
        #expect(effect.entity.children.isEmpty)
        #expect(effect.configuration == nil)
    }

    @Test("The weather's model and the viewer's settings build the same configuration")
    func modelConfiguration() {
        let model = WeatherModel.heavy
        let effect = WeatherTableEffect()
        effect.show(model, in: Self.volume, reduceMotion: false, dimFlashingLights: false)
        #expect(effect.configuration == WeatherSceneConfiguration(model: model, reduceMotion: false, dimFlashingLights: false))
        effect.show(nil, in: Self.volume, reduceMotion: false, dimFlashingLights: false)
        #expect(effect.configuration == nil)
    }
}

/// A repeatable random sequence for the lightning's path (SplitMix64).
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}
#endif
