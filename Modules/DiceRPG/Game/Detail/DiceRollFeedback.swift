// @copyright André Trettin

import Foundation

/// When the roll haptic of the dice overlay fires. A roll changes the dice three times: the results
/// are cleared (`reset(for:)`, "not rolled" is never a success), the roll writes them, and a die's
/// view later resets its rotation. Only the second one is an outcome. See CODE_AUDIT_26 §5.33.
enum DiceRollFeedback {
    /// The per-die results the haptic watches: a rotation-only change leaves them equal.
    static func results(of dice: [DieModel]) -> [[Int]] {
        dice.map(\.result)
    }

    /// Whether `results` hold a rolled outcome; the cleared state before a roll does not.
    static func isRolled(_ results: [[Int]]) -> Bool {
        results.contains { !$0.isEmpty }
    }
}
