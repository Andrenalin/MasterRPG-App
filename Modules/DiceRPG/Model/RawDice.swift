// @copyright André Trettin

import CoreRPG
import Foundation

public struct RawDice: Equatable, Hashable {
    public var modifier: Int = 0
    private var dieCounters: [RawDieCounter] = []

    public init(die: RawDie, modifier: Int = 0) {
        self.modifier = modifier
        addDie(die)
    }

    public init(dice: [RawDie], modifier: Int = 0) {
        self.modifier = modifier
        dice.forEach { addDie($0) }
    }

    public init(dieCounter: RawDieCounter, modifier: Int = 0) {
        self.modifier = modifier
        addDie(dieCounter)
    }

    public init(dieCounters: [RawDieCounter], modifier: Int = 0) {
        self.modifier = modifier
        dieCounters.forEach { addDie($0) }
    }

    public init(text: String) {
        let result = parse(text)
        dieCounters = result.0
        modifier = result.1
    }

    public mutating func addDie(_ dieCounter: RawDieCounter) {
        guard let existingIndex = dieCounters.firstIndex(where: { $0.die.sides == dieCounter.die.sides }) else {
            dieCounters.append(dieCounter)
            return
        }
        var existingDie = dieCounters[existingIndex]
        existingDie.count += dieCounter.count
        if existingDie.count == 0 {
            dieCounters.remove(at: existingIndex)
        } else {
            dieCounters[existingIndex] = existingDie
        }
    }

    public mutating func addDie(_ die: RawDie) {
        addDie(RawDieCounter(die: die))
    }

    public mutating func removeDie(_ dieCounter: RawDieCounter) {
        guard let existingIndex = dieCounters.firstIndex(where: { $0.die.sides == dieCounter.die.sides }) else {
            return
        }
        var existingDie = dieCounters[existingIndex]
        existingDie.count -= dieCounter.count
        if existingDie.count == 0 {
            dieCounters.remove(at: existingIndex)
        } else {
            dieCounters[existingIndex] = existingDie
        }
    }

    public mutating func removeDie(_ die: RawDie) {
        removeDie(RawDieCounter(die: die))
    }

    public func roll() -> Int {
        var result = 0
        dieCounters.forEach { result += $0.roll() }
        return result + modifier
    }

    // Saturating sums: counters and modifiers can come from imported text.
    // See CODE_AUDIT_15 §5.11.
    public var min: Int {
        dieCounters.reduce(0) { $0.saturatingSum($1.min) }.saturatingSum(modifier)
    }

    public var max: Int {
        dieCounters.reduce(0) { $0.saturatingSum($1.max) }.saturatingSum(modifier)
    }

    public var text: String {
        var result = ""
        dieCounters.forEach {
            let text = $0.text
            if $0.count > 0 {
                result += "+"
            }
            result += text
        }
        if modifier > 0 {
            result += "+\(modifier)"
        } else if modifier < 0 {
            result += "\(modifier)"
        }
        if result.hasPrefix("+") {
            result = String(result.dropFirst())
        }
        return result
    }

    private func parse(_ text: String) -> ([RawDieCounter], Int) {
        var modifier = 0
        var dieCounters: [RawDieCounter] = []

        var modifierText = text

        let diePattern = "(?<Die>[+\\-]?[0-9]*d[0-9]+)"
        let dieResults = RegularExpressionParser.parse(text, with: diePattern, extract: ["Die"])
        dieResults.forEach {
            dieCounters.append(RawDieCounter(text: $0))
            modifierText = modifierText.replacing($0, with: "")
        }

        let modifierPattern = "(?<Modifier>[+\\-]+[0-9]+)"
        let modifierResults = RegularExpressionParser.parse(modifierText, with: modifierPattern, extract: ["Modifier"])
        modifierResults.forEach {
            if let number = Int($0) {
                modifier += number
            }
        }
        return (dieCounters, modifier)
    }
}
