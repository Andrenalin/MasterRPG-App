// @copyright André Trettin

import Testing

@testable import CoreRPG

/// CODE_AUDIT §7.5: the undo stack keeps full model copies, so it is bounded.
/// CODE_AUDIT_Edit_Save §5.1-§5.6: it holds steps, which undo and redo move between the stacks.
@MainActor
struct UndoManagedDepthTests {
    @Test func undoStackKeepsOnlyTheNewestSteps() {
        let sut = UndoManaged<Int>()
        let total = UndoManaged<Int>.maxDepth + 25

        for step in 1...total {
            sut.record(step, title: "edit \(step)")
        }

        var undone: [Int] = []
        while sut.canUndo, let step = sut.undo() {
            undone.append(step)
        }
        #expect(undone.count == UndoManaged<Int>.maxDepth)
        #expect(sut.undoTitles.isEmpty)
        #expect(undone.last == total - UndoManaged<Int>.maxDepth + 1, "the oldest steps were dropped, the newest kept")
    }

    @Test func redoReturnsTheUndoneStepAndANewStepClearsRedo() {
        let sut = UndoManaged<Int>()
        sut.record(1, title: "one")
        sut.record(2, title: "two")

        #expect(sut.undo() == 2)
        #expect(sut.canRedo)
        #expect(sut.redo() == 2)
        #expect(sut.undo() == 2)

        sut.record(3, title: "three")
        #expect(!sut.canRedo, "a new edit starts a new branch")
        #expect(sut.nextUndoStep == 3)
    }

    @Test func removingStepsDropsThemFromBothStacks() {
        let sut = UndoManaged<Int>()
        sut.record(1, title: "one")
        sut.record(2, title: "two")
        _ = sut.undo()

        sut.removeAll { $0 == 2 }
        #expect(!sut.canRedo)
        #expect(sut.nextUndoStep == 1)
    }
}
