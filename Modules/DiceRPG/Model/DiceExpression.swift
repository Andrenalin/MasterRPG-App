// @copyright André Trettin

import CoreRPG
import Foundation

/// Dice notation as Siri hears it or a shortcut passes it ("3d6+2", "2 W 20", "D20 plus 5"),
/// reduced to the dice to roll and a flat modifier. Only adds dice: a set cannot subtract a die.
/// See CODE_AUDIT_AppIntents3 §4.6.
public struct DiceExpression: Equatable, Sendable {
    /// Dice one spoken roll may have, so a misheard "300d6" does not hang the reply.
    public static let maximumDice = 100
    /// Sides a die may have; covers d2…d1000.
    public static let sidesRange = 2...1_000

    public struct Term: Equatable, Sendable {
        public let count: Int
        public let sides: Int
    }

    public let terms: [Term]
    public let modifier: Int

    /// `nil` when `input` is not dice notation, has no die, or exceeds the limits.
    public init?(_ input: String) {
        let text = Self.normalized(input)
        guard text.wholeMatch(of: #/\d*d\d+(?:[+\-](?:\d*d\d+|\d+))*/#) != nil else { return nil }

        var terms: [Term] = []
        var modifier = 0
        for match in text.matches(of: #/([+\-]?)(?:(\d*)d(\d+)|(\d+))/#) {
            let sign = match.output.1 == "-" ? -1 : 1
            if let sidesText = match.output.3 {
                // A die can only be added: "1d20-1d4" is refused.
                guard sign > 0, let sides = Int(sidesText), Self.sidesRange.contains(sides) else { return nil }
                let countText = match.output.2 ?? ""
                guard let count = countText.isEmpty ? 1 : Int(countText), count > 0 else { return nil }
                if let index = terms.firstIndex(where: { $0.sides == sides }) {
                    terms[index] = Term(count: terms[index].count.saturatingSum(count), sides: sides)
                } else {
                    terms.append(Term(count: count, sides: sides))
                }
            } else if let numberText = match.output.4, let number = Int(numberText) {
                modifier = modifier.saturatingSum(sign * number)
            } else {
                return nil
            }
        }
        guard !terms.isEmpty, terms.reduce(0, { $0.saturatingSum($1.count) }) <= Self.maximumDice else { return nil }
        self.terms = terms
        self.modifier = modifier
    }

    /// Canonical notation, e.g. `3d6+2`, used as the name of the roll.
    public var text: String {
        let dice = terms.map { "\($0.count == 1 ? "" : "\($0.count)")d\($0.sides)" }.joined(separator: "+")
        switch modifier {
        case 0: return dice
        case 1...: return "\(dice)+\(modifier)"
        default: return "\(dice)\(modifier)"
        }
    }

    /// One die model per die, in the order of the terms.
    public var dieModels: [DieModel] {
        terms.flatMap { term in
            (0..<term.count).map { _ in DieModel(id: UUID(), die: RawDie(.sides(term.sides))) }
        }
    }

    /// Lowercased without spaces; spoken numbers become digits ("two d six"), "plus"/"minus" become
    /// signs, the German "W" (Würfel) and "d%" become `d` notation. "W" is replaced before "%" so
    /// "W%" works, and the number words before "W" because "zwei" contains a "w".
    /// See CODE_AUDIT_Since_3.0.1 §5.21.
    static func normalized(_ input: String) -> String {
        input.lowercased()
            .split(whereSeparator: \.isWhitespace)
            .map { numberWords[String($0)] ?? String($0) }
            .joined()
            .replacing("plus", with: "+")
            .replacing("minus", with: "-")
            .replacing("−", with: "-")
            .replacing("w", with: "d")
            .replacing("d%", with: "d100")
    }

    /// Spoken numbers in English and German, as whole words, up to the common die sizes.
    static let numberWords: [String: String] = [
        "a": "1", "an": "1", "one": "1", "two": "2", "three": "3", "four": "4", "five": "5", "six": "6",
        "seven": "7", "eight": "8", "nine": "9", "ten": "10", "eleven": "11", "twelve": "12",
        "twenty": "20", "hundred": "100",
        "ein": "1", "eins": "1", "eine": "1", "einen": "1", "zwei": "2", "drei": "3", "vier": "4", "fünf": "5",
        "sechs": "6", "sieben": "7", "acht": "8", "neun": "9", "zehn": "10", "elf": "11", "zwölf": "12",
        "zwanzig": "20", "hundert": "100"
    ]
}
