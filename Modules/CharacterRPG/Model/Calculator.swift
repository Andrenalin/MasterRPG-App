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
        return try? Double(nextInput, format: .number.locale(Locale(identifier: "en_US")))
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
        let reg = Regex {
            firstOp
            ZeroOrMore {
                CharacterClass.whitespace
            }
            "/"
            ZeroOrMore {
                CharacterClass.whitespace
            }
            secondOp
        }

        guard let output = input.firstMatch(of: reg) else { return (input, false) }
        let one = output[first]
        let two = output[second]
        let result = one / two
        var nextInput = input
        nextInput.replaceSubrange(output.range, with: formatNumber(result))
        return (nextInput, true)
    }

    @MainActor
    private static func multi(_ input: String) -> (String, Bool) {
        let reg = Regex {
            firstOp
            ZeroOrMore {
                CharacterClass.whitespace
            }
            "*"
            ZeroOrMore {
                CharacterClass.whitespace
            }
            secondOp
        }

        guard let output = input.firstMatch(of: reg) else { return (input, false) }
        let one = output[first]
        let two = output[second]
        let result = one * two
        var nextInput = input
        nextInput.replaceSubrange(output.range, with: formatNumber(result))
        return (nextInput, true)
    }

    @MainActor
    private static func minus(_ input: String) -> (String, Bool) {
        let reg = Regex {
            firstOp
            ZeroOrMore {
                CharacterClass.whitespace
            }
            Optionally("+")
            "-"
            ZeroOrMore {
                CharacterClass.whitespace
            }
            secondOp
        }

        guard let output = input.firstMatch(of: reg) else { return (input, false) }
        let one = output[first]
        let two = output[second]
        let result = one - two
        var nextInput = input
        nextInput.replaceSubrange(output.range, with: formatNumber(result))
        return (nextInput, true)
    }

    @MainActor
    private static func plus(_ input: String) -> (String, Bool) {
        let reg = Regex {
            firstOp
            ZeroOrMore {
                CharacterClass.whitespace
            }
            "+"
            ZeroOrMore {
                CharacterClass.whitespace
            }
            secondOp
        }

        guard let output = input.firstMatch(of: reg) else { return (input, false) }
        let one = output[first]
        let two = output[second]
        let result = one + two
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
