// @copyright André Trettin

#if os(iOS) || os(macOS) || os(visionOS)
import Foundation
import SwiftUI

/// What the 3D weather on the game table shows for a weather: a pure value derived from the
/// weather and the viewer's accessibility settings, so the mapping can be tested without
/// RealityKit. `WeatherTableEffect` builds the entities from it.
struct WeatherSceneConfiguration: Equatable, Sendable {
    enum Precipitation: Equatable, Sendable {
        case none, rain, snow
    }

    /// A color as plain components, so the configuration stays `Equatable` and `Sendable`.
    struct RGBA: Equatable, Sendable {
        var red: Float
        var green: Float
        var blue: Float
        var alpha: Float
    }

    struct Lightning: Equatable, Sendable {
        /// Average strikes per minute, at least one.
        var strikesPerMinute: Double
        /// The bolts of one strike, at least one.
        var maximumBolts: Int
        /// The chance, 0 to 1, that a bolt forks at a bend.
        var forkProbability: Double
    }

    var precipitation: Precipitation
    /// How many drops or flakes fall at once, as the 2D storm's drop count.
    var precipitationCount: Int
    /// Fall speed in meters per second.
    var fallSpeed: Float
    /// The wind's tilt from vertical, in radians. Positive leans the fall toward -X, as a
    /// positive rain angle leans the 2D rain to the left.
    var windTilt: Float
    /// How many clouds float at once; zero shows none.
    var cloudCount: Int
    /// The clouds' opacity before the table's own limit.
    var cloudOpacity: Float
    /// The clouds' color at the weather's time of day, as the 2D clouds are tinted.
    var cloudTint: RGBA
    /// The stars' opacity: one at night, zero by day.
    var starOpacity: Float
    /// `nil` when no lightning strikes.
    var lightning: Lightning?
    /// Whether anything moves. Reduce Motion stops the precipitation and lightning and leaves
    /// the clouds where they are, as the 2D views pause.
    var isAnimated: Bool

    @MainActor
    init(model: WeatherModel, reduceMotion: Bool, dimFlashingLights: Bool) {
        self.init(
            time: model.time,
            cloudThickness: model.cloudThickness,
            stormType: model.stormType,
            rainAngle: model.rainAngle,
            rainIntensity: model.rainIntensity,
            lightningFrequency: model.lightningFrequency,
            lightningMaxBolts: model.lightningMaxBolts,
            lightningForkProbability: model.lightningForkProbability,
            reduceMotion: reduceMotion,
            dimFlashingLights: dimFlashingLights
        )
    }

    /// Reads the 2D viewer's gradients, which belong to the main actor.
    @MainActor
    init(
        time: Double,
        cloudThickness: Cloud.Thickness,
        stormType: Storm.Contents,
        rainAngle: Double,
        rainIntensity: Double,
        lightningFrequency: Double,
        lightningMaxBolts: Double,
        lightningForkProbability: Double,
        reduceMotion: Bool,
        dimFlashingLights: Bool
    ) {
        isAnimated = !reduceMotion

        let strength = WeatherLimits.count(rainIntensity, in: WeatherLimits.rainIntensity)
        switch stormType {
        case .none:
            precipitation = .none
        case .rain:
            precipitation = .rain
        case .snow:
            precipitation = .snow
        }
        // A falling drop is motion: Reduce Motion shows none, as the 2D storm freezes.
        precipitationCount = precipitation == .none || reduceMotion
            ? 0
            : Int((Double(strength) * Self.precipitationScale).rounded())
        fallSpeed = precipitation == .snow ? Self.snowFallSpeed : Self.rainFallSpeed
        let angle = WeatherLimits.clamped(rainAngle, to: WeatherLimits.rainAngle)
        windTilt = Float(angle * .pi / 180) * Self.windTiltFactor

        cloudCount = Self.cloudsAtOnce(for: cloudThickness)
        cloudOpacity = Self.cloudAlpha(for: cloudThickness)
        let clampedTime = WeatherLimits.clamped(time, to: WeatherLimits.time)
        let tint = WeatherViewer.cloudTopStops.interpolated(amount: clampedTime)
            .interpolated(to: WeatherViewer.cloudBottomStops.interpolated(amount: clampedTime), amount: 0.3)
            .getComponents()
        cloudTint = RGBA(red: Float(tint.red), green: Float(tint.green), blue: Float(tint.blue), alpha: 1)
        starOpacity = Float(WeatherViewer.starStops.interpolated(amount: clampedTime).getComponents().alpha)

        let frequency = WeatherLimits.clamped(lightningFrequency, to: WeatherLimits.lightningFrequency)
        let bolts = WeatherLimits.count(lightningMaxBolts, in: WeatherLimits.lightningMaxBolts)
        if frequency >= 1, bolts > 0, !reduceMotion, !dimFlashingLights {
            lightning = Lightning(
                strikesPerMinute: frequency,
                maximumBolts: bolts,
                forkProbability: Double(WeatherLimits.count(lightningForkProbability, in: WeatherLimits.lightningForkProbability)) / 100
            )
        } else {
            lightning = nil
        }
    }

    /// The 2D storm draws up to 1000 drops over a screen; the table's smaller volume needs fewer.
    static let precipitationScale = 0.6
    static let rainFallSpeed: Float = 1.6
    static let snowFallSpeed: Float = 0.12
    /// The 2D rain angle goes to 90°; on the table half of it reads as wind without the drops
    /// flying sideways off the map.
    static let windTiltFactor: Float = 0.5
    /// Below this the stars are not drawn.
    static let visibleOpacity: Float = 0.02

    /// Clouds at once and their opacity come from the per-thickness table shared with 2D,
    /// `Cloud.Thickness.look`.
    static func cloudsAtOnce(for thickness: Cloud.Thickness) -> Int {
        thickness.look.tableCount
    }

    static func cloudAlpha(for thickness: Cloud.Thickness) -> Float {
        thickness.look.tableOpacity
    }
}

/// The box the 3D weather fills, in its parent entity's space: centered on the parent's X/Z
/// origin, from `floorY` up by `height`.
public struct WeatherVolume: Equatable, Sendable {
    public var width: Float
    public var depth: Float
    public var floorY: Float
    public var height: Float
    /// The highest opacity a cloud may have. A table seen from above through its clouds keeps
    /// the map readable with a low limit.
    public var cloudOpacityLimit: Float

    public init(width: Float, depth: Float, floorY: Float, height: Float, cloudOpacityLimit: Float = 1) {
        self.width = max(width, 0.01)
        self.depth = max(depth, 0.01)
        self.floorY = floorY
        self.height = max(height, 0.01)
        self.cloudOpacityLimit = min(max(cloudOpacityLimit, 0), 1)
    }

    var ceilingY: Float { floorY + height }
}
#endif
