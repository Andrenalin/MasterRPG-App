// @copyright André Trettin

import Foundation
import Testing

@testable import DiceRPG

/// CODE_AUDIT_26 §5.33: the roll haptic follows the rolled results only.
@Suite("Dice roll feedback")
struct DiceRollFeedbackTests {
    private func die(result: [Int], rotation: Double = 0) -> DieModel {
        DieModel(id: UUID(), die: .twenty, rotation: rotation, result: result, displayState: 3)
    }

    @Test("The cleared state before a roll is no outcome, a rolled one is")
    func clearedStateIsNotRolled() {
        #expect(!DiceRollFeedback.isRolled(DiceRollFeedback.results(of: [die(result: []), die(result: [])])))
        #expect(!DiceRollFeedback.isRolled([]))
        #expect(DiceRollFeedback.isRolled(DiceRollFeedback.results(of: [die(result: []), die(result: [7])])))
    }

    @Test("A rotation-only change leaves the watched results equal")
    func rotationDoesNotChangeResults() {
        let id = UUID()
        let before = DieModel(id: id, die: .twenty, rotation: 137, result: [12], displayState: 3)
        let after = DieModel(id: id, die: .twenty, rotation: 0, result: [12], displayState: 3)

        #expect(DiceRollFeedback.results(of: [before]) == DiceRollFeedback.results(of: [after]))
    }

    @Test("A new roll changes the watched results")
    func aRollChangesResults() {
        let id = UUID()
        let cleared = DieModel(id: id, die: .twenty, rotation: 0, result: [], displayState: 3)
        let rolled = DieModel(id: id, die: .twenty, rotation: 90, result: [4], displayState: 3)

        #expect(DiceRollFeedback.results(of: [cleared]) != DiceRollFeedback.results(of: [rolled]))
    }
}
