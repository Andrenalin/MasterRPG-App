// @copyright André Trettin

import CoreRPG
import Foundation

public struct RawDieCounter: Equatable, Hashable {
    public var count: Int
    public let die: RawDie

    public init(die: RawDie = RawDie.twenty, count: Int = 1) {
        self.die = die
        self.count = count
    }

    public init(text: String) {
        count = 1
        let pattern = "(?<Count>[\\-0-9]*)(?<Die>d)(?<Sides>[0-9]+)"
        let results = RegularExpressionParser.parse(text, with: pattern, extract: ["Count"])
        if results.count == 1 {
            if results[0] == "-" {
                count = -1
            } else if let number = Int(results[0]) {
                // Notation can come from imported or peer text; an unbounded count made `roll()`
                // loop practically forever and `abs(Int.min)` trap. See CODE_AUDIT_15 §5.11.
                count = Swift.min(Swift.max(number, -Self.maximumCount), Self.maximumCount)
            }
        }
        die = RawDie(text: text)
    }

    public func roll() -> Int {
        // `count == 0` (e.g. parsed from a malformed "0d6" notation string)
        // previously built the invalid range `1...0` and trapped. See
        // CODE_AUDIT §5.7.
        guard count != 0 else { return 0 }
        var result = 0
        (1 ... abs(count)).forEach { _ in result = result.saturatingSum(die.roll()) }
        if count < 0 {
            result *= -1
        }
        return result
    }

    /// Largest number of dice one notation term may stand for.
    public static let maximumCount = 1_000

    public var min: Int {
        count.saturatingProduct(die.min)
    }

    public var max: Int {
        count.saturatingProduct(die.max)
    }

    public var text: String {
        if count == 1 {
            return die.text
        }
        return "\(count)\(die.text)"
    }
}

extension Double {
    /// The nearest `Int`, clamped to `Int.min`/`Int.max`; NaN becomes 0. `Int(_:)` traps on
    /// finite-but-huge values. See CODE_AUDIT_16 §5.4.
    var saturatingInt: Int {
        guard !isNaN else { return 0 }
        // `Double(Int.max)` is 2^63, exactly representable and one past `Int.max`.
        if self >= Double(Int.max) { return .max }
        if self <= Double(Int.min) { return .min }
        return Int(self)
    }
}

extension Int {
    /// `self * other`, clamped to `Int.min`/`Int.max` instead of trapping on overflow.
    func saturatingProduct(_ other: Int) -> Int {
        let (product, overflow) = multipliedReportingOverflow(by: other)
        guard overflow else { return product }
        return (self < 0) == (other < 0) ? Int.max : Int.min
    }

    /// `self + other`, clamped to `Int.min`/`Int.max` instead of trapping on overflow.
    func saturatingSum(_ other: Int) -> Int {
        let (sum, overflow) = addingReportingOverflow(other)
        guard overflow else { return sum }
        return other < 0 ? Int.min : Int.max
    }
}
