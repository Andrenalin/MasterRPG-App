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
        return nextInput.wholeMatch(of: FloatingPointFormatStyle<Double>(locale: Locale(identifier: "en_US")))?.output
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

    private static func formatNumber(_ number: Double) -> String {
        var result = "\(number.formatted(.number.locale(Locale(identifier: "en_US"))))"
        result = result.replacing(",", with: "")
        return result
    }
}
