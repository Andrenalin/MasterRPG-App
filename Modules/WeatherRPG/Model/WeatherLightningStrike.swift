// @copyright André Trettin

import CoreRPG
import Foundation

/// A lightning strike the game master made on a weather: the payload of the weather's
/// `.update/.generic` game message. A player draws the same bolt, at its own screen width.
///
/// It is an event, not state: nothing replays it to a device that joins later, and a device
/// that is not showing the weather ignores it.
public struct WeatherLightningStrike: Codable, Sendable, Equatable, MessageMapper {
    public let weatherId: UUID
    /// Where the main bolt starts across the view's width, from 0 (left) to 1 (right).
    public let startFraction: Double
    /// Seed of the bolt's jitter and forks.
    public let seed: UInt64

    public init(weatherId: UUID, startFraction: Double, seed: UInt64) {
        self.weatherId = weatherId
        self.startFraction = startFraction
        self.seed = seed
    }

    /// Whether the numbers are usable: a peer's payload is not trusted to stay in range.
    public var isValid: Bool {
        startFraction.isFinite && (0 ... 1).contains(startFraction)
    }

    /// The message payload that carries this strike for its weather.
    public var networkData: NetworkCodableDataType {
        NetworkCodableDataType(id: weatherId, type: .weather, version: 0, data: encodeData())
    }

    init(weatherId: UUID, bolt: LightningBoltSpec) {
        self.init(weatherId: weatherId, startFraction: bolt.startFraction, seed: bolt.seed)
    }

    var bolt: LightningBoltSpec {
        LightningBoltSpec(startFraction: startFraction, seed: seed)
    }
}

/// A strike that arrived from the game master, as the viewers of its weather see it.
public struct ReceivedLightningStrike: Equatable, Sendable {
    /// Tells two identical strikes apart for `onChange`.
    let id = UUID()
    public let strike: WeatherLightningStrike
}
