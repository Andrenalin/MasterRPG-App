// @copyright André Trettin

#if os(iOS) || os(macOS) || os(visionOS)
import simd

/// The jagged path of one 3D lightning strike: a main bolt from the cloud layer down to the
/// floor, bending at every step, with forks branching off. Pure, so a seeded generator makes it
/// testable.
enum LightningBoltPath {
    /// One bolt: its points from top to bottom, and how thick it is relative to the main bolt.
    struct Bolt: Equatable, Sendable {
        var points: [SIMD3<Float>]
        var thickness: Float
    }

    /// The bolts of one strike inside `volume`.
    /// - Parameters:
    ///   - maximumBolts: the main bolt plus forks, at least one.
    ///   - forkProbability: the chance, 0 to 1, that a fork starts at a bend.
    static func strike<Generator: RandomNumberGenerator>(
        in volume: WeatherVolume,
        maximumBolts: Int,
        forkProbability: Double,
        using generator: inout Generator
    ) -> [Bolt] {
        let top = volume.floorY + volume.height * cloudLayer
        let start = SIMD3<Float>(
            Float.random(in: -0.4 ... 0.4, using: &generator) * volume.width,
            top,
            Float.random(in: -0.4 ... 0.4, using: &generator) * volume.depth
        )
        let stepLength = (top - volume.floorY) / Float(steps)
        let jitter = stepLength * jitterFactor

        var bolts = [Bolt(points: [start], thickness: 1)]
        var index = 0
        while index < bolts.count {
            var bolt = bolts[index]
            let isMain = index == 0
            // A fork leans away and stops part way down; the main bolt reaches the floor.
            let lean = isMain
                ? SIMD3<Float>.zero
                : SIMD3<Float>(
                    Float.random(in: -1 ... 1, using: &generator),
                    0,
                    Float.random(in: -1 ... 1, using: &generator)
                ) * stepLength * forkLean
            let remaining = isMain ? steps : max(2, steps / 2 - bolt.points.count / 2)
            for step in 0 ..< remaining {
                guard let last = bolt.points.last else { break }
                var next = last + lean
                next.x += Float.random(in: -jitter ... jitter, using: &generator)
                next.z += Float.random(in: -jitter ... jitter, using: &generator)
                // The main bolt's last bend touches the floor exactly, whatever rounding left.
                next.y = isMain && step == remaining - 1
                    ? volume.floorY
                    : max(volume.floorY, last.y - stepLength)
                bolt.points.append(next)
                if bolts.count < maximumBolts,
                   Double.random(in: 0 ..< 1, using: &generator) < forkProbability {
                    bolts.append(Bolt(points: [next], thickness: bolt.thickness * forkThickness))
                }
                if next.y <= volume.floorY { break }
            }
            bolts[index] = bolt
            index += 1
        }
        return bolts
    }

    /// The share of the volume's height where bolts start: the clouds' layer.
    static let cloudLayer: Float = 0.85
    /// Bends from the clouds to the floor.
    static let steps = 12
    /// The sideways jitter of a bend, relative to a step's length.
    static let jitterFactor: Float = 0.6
    /// How far a fork leans away per step, relative to a step's length.
    static let forkLean: Float = 0.5
    /// A fork's thickness relative to the bolt it branches from.
    static let forkThickness: Float = 0.6
}
#endif
