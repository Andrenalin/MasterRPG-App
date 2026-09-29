// @copyright André Trettin

import Foundation
import Testing

@testable import CoreRPG

/// CODE_AUDIT_19 §5.13: persistence failures reach the UI, and only a real save clears a save
/// error. Discarded edits and file errors stay until the user dismisses them.
@MainActor
@Suite("Persistence issue center")
struct PersistenceIssueCenterTests {
    private struct SaveFailure: LocalizedError {
        var errorDescription: String? { "Disk full" }
    }

    @Test("A successful save clears only the save error")
    func successfulSaveClearsSaveError() {
        let sut = PersistenceIssueCenter()
        sut.recordSaveError(SaveFailure())
        sut.recordFileError(SaveFailure())
        sut.recordDiscardedEdits(2)
        #expect(sut.saveError == "Disk full")

        sut.recordSuccessfulSave()

        #expect(sut.saveError == nil)
        #expect(sut.fileError == "Disk full")
        #expect(sut.discardedEditCount == 2)
        #expect(sut.hasIssue)
    }

    @Test("Dismiss clears every issue")
    func dismissClearsEverything() {
        let sut = PersistenceIssueCenter()
        sut.recordSaveError(SaveFailure())
        sut.recordFileError(SaveFailure())
        sut.recordDiscardedEdits(1)

        sut.dismiss()

        #expect(!sut.hasIssue)
    }
}
