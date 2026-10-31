// @copyright André Trettin

import Foundation

/// The bounds of a whole number on a character sheet, in the battle card and in the quick
/// editors. A number typed into a field, resolved from a formula or sent by an intent can be any
/// `Int` or `Double`, and `Int(Double)` and `+` trap outside the range; everything that stores or
/// steps such a number clamps it with this first. A trillion is far above any hit point or gold
/// total and far below where `Double` stops counting exactly. See CODE_AUDIT_22 §5.5, §5.6.
public enum SheetNumberLimit {
    public static let maximumMagnitude = 1_000_000_000_000

    /// `value` inside `±maximumMagnitude`.
    public static func clamped(_ value: Int) -> Int {
        min(max(value, -maximumMagnitude), maximumMagnitude)
    }

    /// `value` rounded to a whole number inside `±maximumMagnitude`; NaN is 0, infinity the bound.
    public static func clamped(_ value: Double) -> Int {
        guard !value.isNaN else { return 0 }
        let limit = Double(maximumMagnitude)
        return Int(min(max(value.rounded(), -limit), limit))
    }

    /// The sum of two numbers, clamped. Both are clamped first, so the addition cannot overflow.
    public static func sum(_ lhs: Int, _ rhs: Int) -> Int {
        clamped(clamped(lhs) + clamped(rhs))
    }
}
