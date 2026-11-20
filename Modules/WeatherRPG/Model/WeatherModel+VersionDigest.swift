// @copyright André Trettin

import CoreRPG
import Foundation

extension WeatherModel {
    /// Deterministic identity of what players see of a Weather: its sky and storm settings and
    /// the version of the linked Photo (`0` without one). A reshow after an edit carries a new
    /// version, so the players' cached package is replaced. Name, tags and list position are
    /// deliberately not part of it. See CODE_AUDIT §5.7.
    func contentVersion(photoVersion: Int) -> Int {
        StableVersionDigest.digest(CanonicalWeatherContent(self, photoVersion: photoVersion))
    }
}

private struct CanonicalWeatherContent: Codable, Sendable {
    let photoVersion: Int
    let time: Double
    let cloudThickness: Int
    let stormType: Int
    let rainAngle: Double
    let rainIntensity: Double
    let lightningFrequency: Double
    let lightningMaxBolts: Double
    let lightningForkProbability: Double

    @MainActor
    init(_ model: WeatherModel, photoVersion: Int) {
        self.photoVersion = photoVersion
        time = model.time
        cloudThickness = model.cloudThickness.rawValue
        stormType = model.stormType.rawValue
        rainAngle = model.rainAngle
        rainIntensity = model.rainIntensity
        lightningFrequency = model.lightningFrequency
        lightningMaxBolts = model.lightningMaxBolts
        lightningForkProbability = model.lightningForkProbability
    }
}
