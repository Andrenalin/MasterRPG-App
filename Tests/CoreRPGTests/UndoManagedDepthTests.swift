// @copyright André Trettin

import Testing

@testable import CoreRPG

/// CODE_AUDIT §7.5: the undo stack keeps full model copies, so it is bounded.
@MainActor
struct UndoManagedDepthTests {
    @Test func undoStackKeepsOnlyTheNewestSteps() {
        let sut = UndoManaged<Int>(initialValue: 0)
        let total = UndoManaged<Int>.maxDepth + 25

        for step in 1...total {
            sut.previousValue(step - 1, title: "edit \(step)")
            sut.updateValue(step)
        }

        var undone = 0
        while sut.canUndo {
            sut.undo()
            undone += 1
        }
        #expect(undone == UndoManaged<Int>.maxDepth)
        #expect(sut.undoTitles.isEmpty)
        #expect(sut.value == total - UndoManaged<Int>.maxDepth, "the oldest steps were dropped, the newest kept")
    }
}
