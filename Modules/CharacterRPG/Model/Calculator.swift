// @copyright André Trettin

import Foundation
import RegexBuilder

struct Calculator {
    // "4 +6 -4* 2+4 *  3"
    // "4 +6 -8.0+12.0"
    // "4 +-2.0+12"
    @MainActor static func calculate(_ input: String) -> Double? {
        var nextInput = input.trimmingCharacters(in: .whitespacesAndNewlines)
        var hasOp = true
        while hasOp {
            (nextInput, hasOp) = divide(nextInput)
        }
        hasOp = true
        while hasOp {
            (nextInput, hasOp) = multi(nextInput)
        }
        hasOp = true
        while hasOp {
            (nextInput, hasOp) = minus(nextInput)
        }
        hasOp = true
        while hasOp {
            (nextInput, hasOp) = plus(nextInput)
        }
        // `Double(_:format:)` does prefix matching (e.g. "2-" parses as 2.0, silently
        // ignoring the trailing "-"), unlike the strict NumberFormatter this replaced.
        // `wholeMatch(of:)` requires the entire string to match, restoring that behavior.
        guard let value = nextInput.wholeMatch(of: FloatingPointFormatStyle<Double>(locale: Locale(identifier: "en_US")))?.output else {
            return nil
        }
        return roundedToResultPrecision(value)
    }

    /// The steps carry a `Double` exactly (see `formatNumber`), so binary noise such as the 4e-17 of
    /// 0.1 + 0.2 survives to the end. The final result is rounded to 15 significant digits, which
    /// collapses that noise and leaves every number a sheet can hold unchanged.
    /// See CODE_AUDIT_22 §5.7, CODE_AUDIT_22a §5.4.
    private static func roundedToResultPrecision(_ value: Double) -> Double {
        guard value.isFinite, value != 0 else { return value }
        let text = value.formatted(
            .number
                .locale(Locale(identifier: "en_US"))
                .grouping(.never)
                .precision(.significantDigits(1 ... 15))
        )
        return (try? Double(text, format: .number.locale(Locale(identifier: "en_US")), lenient: false)) ?? value
    }

    @MainActor
    static let first = Reference(Double.self)
    @MainActor
    static let second = Reference(Double.self)

    @MainActor
    static let firstOp = Regex {
        ZeroOrMore {
            CharacterClass.whitespace
        }
        TryCapture(as: first) {
            OneOrMore {
                .localizedDecimal(locale: Locale(identifier: "en_US"))
            }
        } transform: { match in
            Double(match)
        }
    }

    @MainActor
    static let secondOp = Regex {
        TryCapture(as: second) {
            OneOrMore {
                .localizedDecimal(locale: Locale(identifier: "en_US"))
            }
        } transform: { match in
            Double(match)
        }
    }

    @MainActor
    private static func divide(_ input: String) -> (String, Bool) {
        apply(input, symbol: "/", allowLeadingPlus: false) { $0 / $1 }
    }

    @MainActor
    private static func multi(_ input: String) -> (String, Bool) {
        apply(input, symbol: "*", allowLeadingPlus: false) { $0 * $1 }
    }

    @MainActor
    private static func minus(_ input: String) -> (String, Bool) {
        // Allows a leading "+" before the "-" so double-signed input like "4 +-2" still matches.
        apply(input, symbol: "-", allowLeadingPlus: true) { $0 - $1 }
    }

    @MainActor
    private static func plus(_ input: String) -> (String, Bool) {
        apply(input, symbol: "+", allowLeadingPlus: false) { $0 + $1 }
    }

    @MainActor
    private static func apply(
        _ input: String,
        symbol: String,
        allowLeadingPlus: Bool,
        operation: (Double, Double) -> Double
    ) -> (String, Bool) {
        // An always-present `Optionally` sidesteps a result-builder inference failure that
        // shows up when a runtime `if` guards a builder component here; matching an empty
        // string is a harmless no-op, so this behaves identically to omitting it outright.
        let leadingPlus = allowLeadingPlus ? "+" : ""
        let reg = Regex {
            firstOp
            ZeroOrMore {
                CharacterClass.whitespace
            }
            Optionally(leadingPlus)
            symbol
            ZeroOrMore {
                CharacterClass.whitespace
            }
            secondOp
        }

        guard let output = input.firstMatch(of: reg) else { return (input, false) }
        let one = output[first]
        let two = output[second]
        let result = operation(one, two)
        var nextInput = input
        nextInput.replaceSubrange(output.range, with: formatNumber(result))
        return (nextInput, true)
    }

    /// An intermediate result as the text the next step parses. The text keeps up to 17 significant
    /// digits, which is exact for a `Double`: "1/3*3" is 1, not the 0.999 that the default `.number`
    /// style (three fraction digits) rounded to after the first step.
    /// See CODE_AUDIT_22 §5.7, CODE_AUDIT_22a §5.4.
    private static func formatNumber(_ number: Double) -> String {
        number.formatted(
            .number
                .locale(Locale(identifier: "en_US"))
                .grouping(.never)
                .precision(.significantDigits(1 ... 17))
        )
    }
}
