// @copyright André Trettin

import Foundation

/// The range of each weather value, as the editors' sliders offer it. A value that arrives from an
/// import, a peer or a synced store is not bound by a slider: `Int(Double)` on NaN, infinity or
/// 1e300 traps, and `0 ..< strength` traps for a negative strength. Every decode and load clamps
/// to these ranges. See CODE_AUDIT_22 §5.3.
enum WeatherLimits {
    static let time: ClosedRange<Double> = 0 ... 1
    static let rainIntensity: ClosedRange<Double> = 0 ... 1000
    static let rainAngle: ClosedRange<Double> = -90 ... 90
    static let lightningFrequency: ClosedRange<Double> = 0 ... 100
    static let lightningMaxBolts: ClosedRange<Double> = 0 ... 10
    static let lightningForkProbability: ClosedRange<Double> = 0 ... 100

    /// `value` inside `range`; NaN and infinities become the lower bound or the nearest bound.
    static func clamped(_ value: Double, to range: ClosedRange<Double>) -> Double {
        guard !value.isNaN else { return range.lowerBound }
        return min(max(value, range.lowerBound), range.upperBound)
    }

    /// `clamped(_:to:)` as a whole number, for the animation counts.
    static func count(_ value: Double, in range: ClosedRange<Double>) -> Int {
        Int(clamped(value, to: range))
    }
}
