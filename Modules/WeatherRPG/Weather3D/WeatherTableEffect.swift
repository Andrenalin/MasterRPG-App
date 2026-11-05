// @copyright André Trettin

#if os(iOS) || os(macOS) || os(visionOS)
import CoreRPG
import Foundation
import RealityKit
import SwiftUI
import os.log

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// A weather in 3D, without its photo, for the game table: rain or snow falling onto the map,
/// drifting clouds, stars at night and lightning. Add `entity` where the weather's volume is
/// measured from, then call `show(_:in:reduceMotion:dimFlashingLights:)` on every change.
@MainActor
public final class WeatherTableEffect {
    /// The weather's root. Its children are rebuilt for each new weather.
    public let entity: Entity

    /// What is shown, `nil` while no weather is.
    private(set) var configuration: WeatherSceneConfiguration?
    private(set) var volume: WeatherVolume?
    private var lightningTask: Task<Void, Never>?

    public init() {
        entity = Entity()
        entity.name = Self.rootName
    }

    isolated deinit {
        lightningTask?.cancel()
    }

    /// Whether a weather is shown.
    public var isShowing: Bool {
        configuration != nil
    }

    /// Shows `model` inside `volume`, or nothing for `nil`. Runs on every map sync, so an
    /// unchanged weather and volume leave the running particles alone.
    public func show(
        _ model: WeatherModel?,
        in volume: WeatherVolume,
        reduceMotion: Bool,
        dimFlashingLights: Bool
    ) {
        guard let model else {
            hide()
            return
        }
        show(
            WeatherSceneConfiguration(model: model, reduceMotion: reduceMotion, dimFlashingLights: dimFlashingLights),
            in: volume
        )
    }

    /// Removes the weather.
    public func hide() {
        removeWeather()
        configuration = nil
        volume = nil
    }

    func show(_ configuration: WeatherSceneConfiguration, in volume: WeatherVolume) {
        guard configuration != self.configuration || volume != self.volume else { return }
        removeWeather()
        self.configuration = configuration
        self.volume = volume

        if configuration.starOpacity >= WeatherSceneConfiguration.visibleOpacity {
            entity.addChild(Self.stars(configuration, in: volume))
        }
        if configuration.cloudCount > 0, configuration.cloudOpacity * volume.cloudOpacityLimit > 0 {
            entity.addChild(Self.clouds(configuration, in: volume))
        }
        if configuration.precipitationCount > 0 {
            entity.addChild(Self.precipitation(configuration, in: volume))
        }
        if let lightning = configuration.lightning {
            startLightning(lightning, in: volume)
        }
    }

    private func removeWeather() {
        lightningTask?.cancel()
        lightningTask = nil
        entity.children.removeAll()
    }

    // MARK: - Lightning

    private func startLightning(_ lightning: WeatherSceneConfiguration.Lightning, in volume: WeatherVolume) {
        let container = Entity()
        container.name = Self.lightningName
        entity.addChild(container)
        let interval = 60 / max(lightning.strikesPerMinute, 1)
        lightningTask = Task { [weak container] in
            var generator = SystemRandomNumberGenerator()
            while !Task.isCancelled {
                // Strikes come irregularly around the weather's frequency, as in 2D.
                try? await Task.sleep(for: .seconds(Double.random(in: interval * 0.5 ... interval * 1.5)))
                guard !Task.isCancelled, let container else { return }
                let bolts = LightningBoltPath.strike(
                    in: volume,
                    maximumBolts: lightning.maximumBolts,
                    forkProbability: lightning.forkProbability,
                    using: &generator
                )
                let strike = Self.strike(bolts, in: volume)
                container.addChild(strike)
                try? await Task.sleep(for: Self.strikeDuration)
                strike.removeFromParent()
            }
        }
    }

    static func strike(_ bolts: [LightningBoltPath.Bolt], in volume: WeatherVolume) -> Entity {
        let strike = Entity()
        strike.name = "Strike"
        let material = UnlitMaterial(color: .white)
        for bolt in bolts {
            for (start, end) in zip(bolt.points, bolt.points.dropFirst()) {
                let segment = end - start
                let length = simd_length(segment)
                guard length > 0 else { continue }
                let thickness = boltThickness * bolt.thickness
                let piece = ModelEntity(mesh: boltMesh, materials: [material])
                piece.position = (start + end) / 2
                piece.orientation = simd_quatf(from: [0, 1, 0], to: segment / length)
                piece.scale = [thickness, length, thickness]
                strike.addChild(piece)
            }
        }
        if let origin = bolts.first?.points.first {
            // The flash lights the table under the clouds for as long as the bolt shows.
            let flash = Entity()
            flash.position = origin
            flash.components.set(PointLightComponent(
                cgColor: CGColor(red: 0.85, green: 0.9, blue: 1, alpha: 1),
                intensity: flashIntensity,
                attenuationRadius: max(volume.width, volume.depth) * 1.5
            ))
            strike.addChild(flash)
        }
        return strike
    }

    // MARK: - Particles

    static func precipitation(_ configuration: WeatherSceneConfiguration, in volume: WeatherVolume) -> Entity {
        let isSnow = configuration.precipitation == .snow
        var emitter = isSnow ? ParticleEmitterComponent.Presets.snow : ParticleEmitterComponent.Presets.rain
        let fallHeight = volume.height * LightningBoltPath.cloudLayer
        let direction = SIMD3<Float>(-sin(configuration.windTilt), -cos(configuration.windTilt), 0)
        let verticalSpeed = max(configuration.fallSpeed * cos(configuration.windTilt), 0.01)
        // Drops end at the table top instead of falling through it.
        let lifeSpan = Double(fallHeight / verticalSpeed)

        emitter.emitterShape = .plane
        emitter.birthLocation = .surface
        emitter.birthDirection = .local
        emitter.emitterShapeSize = [volume.width, 0, volume.depth]
        emitter.emissionDirection = direction
        emitter.speed = configuration.fallSpeed
        emitter.speedVariation = configuration.fallSpeed * 0.15
        emitter.particlesInheritTransform = true
        emitter.spawnedEmitter = nil
        // Already falling when the weather appears.
        emitter.timing = .repeating(warmUp: lifeSpan, emit: .init(duration: emitDuration))

        var particle = emitter.mainEmitter
        particle.lifeSpan = lifeSpan
        particle.lifeSpanVariation = 0
        particle.birthRate = Float(Double(configuration.precipitationCount) / lifeSpan)
        particle.birthRateVariation = 0
        particle.acceleration = .zero
        particle.dampingFactor = 0
        particle.spreadingAngle = 0
        particle.noiseStrength = isSnow ? 0.04 : 0
        particle.noiseScale = 1
        particle.noiseAnimationSpeed = isSnow ? 0.3 : 0
        particle.size = isSnow ? 0.006 : 0.0025
        particle.sizeVariation = particle.size * 0.3
        particle.billboardMode = isSnow ? .billboard : .billboardYAligned
        particle.stretchFactor = isSnow ? 0 : 3
        particle.opacityCurve = .quickFadeInOut
        particle.color = .constant(.single(.init(white: 1, alpha: isSnow ? 0.95 : 0.7)))
        particle.isLightingEnabled = false
        particle.blendMode = .alpha
        if let texture = WeatherTextures.texture(named: isSnow ? "snow" : "rain") {
            particle.image = texture
        }
        emitter.mainEmitter = particle

        let precipitation = Entity()
        precipitation.name = precipitationName
        // Moved against the wind, so the drops land on the map instead of beside it.
        precipitation.position = [fallHeight * tan(configuration.windTilt), volume.floorY + fallHeight, 0]
        precipitation.components.set(emitter)
        return precipitation
    }

    static func clouds(_ configuration: WeatherSceneConfiguration, in volume: WeatherVolume) -> Entity {
        var emitter = ParticleEmitterComponent()
        let lifeSpan = cloudLifeSpan
        emitter.emitterShape = .box
        emitter.birthLocation = .volume
        emitter.birthDirection = .local
        emitter.emitterShapeSize = [volume.width, volume.height * 0.08, volume.depth]
        emitter.emissionDirection = simd_normalize(SIMD3<Float>(1, 0, 0.2))
        // Reduce Motion: the clouds stay where they appear.
        emitter.speed = configuration.isAnimated ? cloudSpeed : 0
        emitter.speedVariation = configuration.isAnimated ? cloudSpeed * 0.3 : 0
        emitter.particlesInheritTransform = true
        emitter.timing = .repeating(warmUp: lifeSpan, emit: .init(duration: emitDuration))

        var particle = emitter.mainEmitter
        particle.lifeSpan = lifeSpan
        particle.lifeSpanVariation = lifeSpan * 0.2
        particle.birthRate = Float(Double(configuration.cloudCount) / lifeSpan)
        particle.birthRateVariation = 0
        particle.acceleration = .zero
        particle.noiseStrength = 0
        particle.size = min(volume.width, volume.depth) * 0.35
        particle.sizeVariation = particle.size * 0.3
        particle.billboardMode = .billboard
        particle.opacityCurve = .gradualFadeInOut
        let tint = configuration.cloudTint
        particle.color = .constant(.single(.init(
            red: CGFloat(tint.red),
            green: CGFloat(tint.green),
            blue: CGFloat(tint.blue),
            alpha: CGFloat(configuration.cloudOpacity * volume.cloudOpacityLimit)
        )))
        particle.isLightingEnabled = false
        particle.blendMode = .alpha
        if let texture = WeatherTextures.texture(named: cloudTextureName(for: configuration.cloudCount)) {
            particle.image = texture
        }
        emitter.mainEmitter = particle

        let clouds = Entity()
        clouds.name = cloudsName
        clouds.position = [0, volume.floorY + volume.height * LightningBoltPath.cloudLayer, 0]
        clouds.components.set(emitter)
        return clouds
    }

    static func stars(_ configuration: WeatherSceneConfiguration, in volume: WeatherVolume) -> Entity {
        var emitter = ParticleEmitterComponent()
        // Twinkling is motion: with Reduce Motion the stars just stay.
        let lifeSpan = configuration.isAnimated ? starTwinkle : cloudLifeSpan * 2
        emitter.emitterShape = .plane
        emitter.birthLocation = .surface
        emitter.emitterShapeSize = [volume.width * 1.1, 0, volume.depth * 1.1]
        emitter.speed = 0
        emitter.speedVariation = 0
        emitter.particlesInheritTransform = true
        emitter.timing = .repeating(warmUp: lifeSpan, emit: .init(duration: emitDuration))

        var particle = emitter.mainEmitter
        particle.lifeSpan = lifeSpan
        particle.lifeSpanVariation = lifeSpan * 0.4
        particle.birthRate = Float(Double(starCount) / lifeSpan)
        particle.acceleration = .zero
        particle.size = 0.003
        particle.sizeVariation = 0.0015
        particle.billboardMode = .billboard
        particle.opacityCurve = configuration.isAnimated ? .quickFadeInOut : .constant
        particle.color = .constant(.single(.init(white: 1, alpha: CGFloat(configuration.starOpacity))))
        particle.isLightingEnabled = false
        particle.blendMode = .additive
        emitter.mainEmitter = particle

        let stars = Entity()
        stars.name = starsName
        stars.position = [0, volume.ceilingY, 0]
        stars.components.set(emitter)
        return stars
    }

    /// Thicker cover uses the denser cloud images.
    static func cloudTextureName(for cloudCount: Int) -> String {
        "cloud\(min(max(cloudCount / 2, 0), 7))"
    }

    // MARK: - Constants

    static let rootName = "TableWeather"
    static let precipitationName = "Precipitation"
    static let cloudsName = "Clouds"
    static let starsName = "Stars"
    static let lightningName = "Lightning"

    /// Long enough that an emitter never stops while a weather is shown.
    private static let emitDuration: TimeInterval = 24 * 60 * 60
    private static let cloudLifeSpan: TimeInterval = 24
    private static let cloudSpeed: Float = 0.015
    private static let starTwinkle: TimeInterval = 4
    private static let starCount = 60
    private static let boltThickness: Float = 0.003
    private static let flashIntensity: Float = 12_000
    private static let strikeDuration: Duration = .milliseconds(150)
    private static let boltMesh = MeshResource.generateBox(size: 1)
}

/// The 2D weather's images as particle textures, loaded once.
@MainActor
enum WeatherTextures {
    private static var cache: [String: TextureResource] = [:]

    static func texture(named name: String) -> TextureResource? {
        if let texture = cache[name] {
            return texture
        }
        guard let image = Image.loadImage(name: name), let cgImage = cgImage(from: image) else {
            Logger.weather3D.error("Missing weather texture \(name, privacy: .public)")
            return nil
        }
        do {
            let texture = try TextureResource(image: cgImage, withName: "weather-\(name)", options: .init(semantic: .color))
            cache[name] = texture
            return texture
        } catch {
            Logger.weather3D.error("Weather texture \(name, privacy: .public) failed: \(error.localizedDescription, privacy: .private)")
            return nil
        }
    }

    private static func cgImage(from image: AKImage) -> CGImage? {
#if os(macOS)
        image.cgImage(forProposedRect: nil, context: nil, hints: nil)
#else
        image.cgImage
#endif
    }
}

extension Logger {
    static let weather3D = Logger(subsystem: subsystem, category: "Weather3D")
}
#endif
