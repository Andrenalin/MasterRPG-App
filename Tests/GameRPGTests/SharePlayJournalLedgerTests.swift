// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import Foundation
import Testing

@testable import GameRPG

/// The upload rule of the SharePlay Journal: one slot per module, never twice for one show,
/// and again for a later show only after a minute.
@Suite("SharePlay Journal ledger")
struct SharePlayJournalLedgerTests {
    let photoId = UUID()
    let start = ContinuousClock.now

    func uploaded(counter: Int = 5, version: Int = 3, at instant: ContinuousClock.Instant? = nil) -> SharePlayJournalLedger {
        var ledger = SharePlayJournalLedger()
        ledger.willUpload(module: .photo, itemId: photoId, version: version, counter: counter, now: instant ?? start)
        ledger.didUpload(module: .photo, itemId: photoId, version: version, counter: counter, attachmentId: UUID())
        return ledger
    }

    @Test("An empty slot uploads")
    func emptySlotUploads() {
        let ledger = SharePlayJournalLedger()

        #expect(ledger.shouldUpload(module: .photo, itemId: photoId, version: 3, counter: 5, now: start))
    }

    @Test("Another item or another version of the slot's item uploads")
    func otherItemOrVersionUploads() {
        let ledger = uploaded()

        #expect(ledger.shouldUpload(module: .photo, itemId: UUID(), version: 3, counter: 5, now: start))
        #expect(ledger.shouldUpload(module: .photo, itemId: photoId, version: 4, counter: 5, now: start))
    }

    @Test("Each module has its own slot")
    func modulesAreIndependent() {
        let ledger = uploaded()

        #expect(ledger.shouldUpload(module: .pdf, itemId: photoId, version: 3, counter: 5, now: start))
    }

    @Test("A request for the show that was already uploaded never uploads again")
    func sameShowNeverUploadsTwice() {
        let ledger = uploaded(counter: 5)
        let muchLater = start + .seconds(600)

        #expect(!ledger.shouldUpload(module: .photo, itemId: photoId, version: 3, counter: 5, now: muchLater))
        #expect(!ledger.shouldUpload(module: .photo, itemId: photoId, version: 3, counter: 4, now: muchLater))
    }

    @Test("A later show within a minute of the upload does not upload again")
    func laterShowWithinTheIntervalDoesNotUpload() {
        let ledger = uploaded(counter: 5)

        #expect(!ledger.shouldUpload(module: .photo, itemId: photoId, version: 3, counter: 6, now: start + .seconds(59)))
        #expect(!ledger.shouldUpload(module: .photo, itemId: photoId, version: 3, counter: 6, now: start + SharePlayJournalLedger.reuploadInterval))
    }

    @Test("A later show more than a minute after the upload uploads again")
    func laterShowAfterTheIntervalUploads() {
        let ledger = uploaded(counter: 5)

        #expect(ledger.shouldUpload(module: .photo, itemId: photoId, version: 3, counter: 6, now: start + .seconds(61)))
    }

    @Test("The upload is reserved while it is still running")
    func runningUploadReservesTheSlot() {
        // Given: queued, not finished.
        var ledger = SharePlayJournalLedger()
        ledger.willUpload(module: .photo, itemId: photoId, version: 3, counter: 5, now: start)

        // Then: a second player asking for the same show starts no second upload.
        #expect(!ledger.shouldUpload(module: .photo, itemId: photoId, version: 3, counter: 5, now: start))
    }

    @Test("A failed upload frees the slot")
    func failedUploadFreesTheSlot() {
        // Given
        var ledger = SharePlayJournalLedger()
        ledger.willUpload(module: .photo, itemId: photoId, version: 3, counter: 5, now: start)

        // When
        ledger.uploadFailed(module: .photo, itemId: photoId, version: 3, counter: 5)

        // Then
        #expect(ledger.shouldUpload(module: .photo, itemId: photoId, version: 3, counter: 5, now: start))
    }

    @Test("A failure report of an older upload does not free a newer one")
    func failureOfAnOlderUploadIsIgnored() {
        // Given
        var ledger = SharePlayJournalLedger()
        ledger.willUpload(module: .photo, itemId: photoId, version: 3, counter: 5, now: start)
        ledger.willUpload(module: .photo, itemId: photoId, version: 4, counter: 6, now: start)

        // When
        ledger.uploadFailed(module: .photo, itemId: photoId, version: 3, counter: 5)

        // Then
        #expect(!ledger.shouldUpload(module: .photo, itemId: photoId, version: 4, counter: 6, now: start))
    }

    @Test("An attachment that left the Journal can be uploaded again")
    func removedAttachmentUploadsAgain() throws {
        // Given
        var ledger = uploaded(counter: 5)
        let attachmentId = try #require(ledger.publication(for: .photo)?.attachmentId)

        // When
        ledger.didRemove(attachmentId: attachmentId)

        // Then
        #expect(ledger.shouldUpload(module: .photo, itemId: photoId, version: 3, counter: 5, now: start))
    }

    @Test("A Journal snapshot without the attachment forgets it; a running upload stays reserved")
    func snapshotReconcilesPublications() {
        // Given
        var finished = uploaded(counter: 5)
        var running = SharePlayJournalLedger()
        running.willUpload(module: .photo, itemId: photoId, version: 3, counter: 5, now: start)

        // When
        finished.reconcile(attachmentIds: [])
        running.reconcile(attachmentIds: [])

        // Then
        #expect(finished.shouldUpload(module: .photo, itemId: photoId, version: 3, counter: 5, now: start))
        #expect(!running.shouldUpload(module: .photo, itemId: photoId, version: 3, counter: 5, now: start))
    }

    @Test("A received attachment is handed to the game once")
    func attachmentIsProcessedOnce() {
        // Given
        var ledger = SharePlayJournalLedger()
        let attachmentId = UUID()

        // When
        let first = ledger.shouldProcess(attachmentId: attachmentId)
        let second = ledger.shouldProcess(attachmentId: attachmentId)
        // Its bytes did not load: the next snapshot tries again.
        ledger.retryProcessing(attachmentId: attachmentId)
        let afterRetry = ledger.shouldProcess(attachmentId: attachmentId)

        // Then
        #expect(first)
        #expect(!second)
        #expect(afterRetry)
    }

    @Test("This device's own upload is not handed back to its game")
    func ownUploadIsNotProcessed() throws {
        // Given
        var ledger = uploaded()
        let attachmentId = try #require(ledger.publication(for: .photo)?.attachmentId)

        // When
        let processes = ledger.shouldProcess(attachmentId: attachmentId)

        // Then
        #expect(!processes)
    }

    @Test("A reset forgets everything")
    func reset() {
        // Given
        var ledger = uploaded()

        // When
        ledger.reset()

        // Then
        #expect(ledger.publication(for: .photo) == nil)
        #expect(ledger.shouldUpload(module: .photo, itemId: photoId, version: 3, counter: 5, now: start))
    }
}
#endif
