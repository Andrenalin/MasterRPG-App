// @copyright André Trettin

import Foundation
import Testing

@testable import CoreRPG

/// CODE_AUDIT_26 §5.21: only a saved game ends "Save and Quit".
@Suite("Export panel result")
struct ExportPanelResultTests {
    @Test("Each way the panel ends maps to a result; running states have none yet")
    func outcomesMapToResults() {
        typealias Outcome = ExportProgressPanelView.ExportOutcome
        #expect(Outcome.finished.panelResult == .finished)
        #expect(Outcome.cancelled.panelResult == .cancelled)
        #expect(Outcome.failed("disk full").panelResult == .failed)
        #expect(Outcome.running.panelResult == nil)
        #expect(Outcome.notStarted.panelResult == nil)
    }

    @Test("Save and Quit quits after a finished save only, not after Cancel, a swipe-down or a failure")
    func onlyAFinishedSaveQuits() {
        #expect(ExportPanelResult.finished.endsSaveAndQuit)
        #expect(!ExportPanelResult.cancelled.endsSaveAndQuit)
        #expect(!ExportPanelResult.failed.endsSaveAndQuit)
    }
}
