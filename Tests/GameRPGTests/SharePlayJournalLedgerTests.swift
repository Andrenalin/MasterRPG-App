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

    func show(
        _ module: NetworkModules,
        _ itemId: UUID,
        _ version: Int,
        _ counter: Int,
        isPlaylist: Bool = false
    ) -> SharePlayJournalLedger.Show {
        SharePlayJournalLedger.Show(
            slot: SharePlayJournalSlot(module, isPlaylist: isPlaylist),
            itemId: itemId,
            version: version,
            counter: counter
        )
    }

    func uploaded(counter: Int = 5, version: Int = 3, at instant: ContinuousClock.Instant? = nil) -> SharePlayJournalLedger {
        var ledger = SharePlayJournalLedger()
        ledger.willUpload(show(.photo, photoId, version, counter), now: instant ?? start)
        ledger.didUpload(show(.photo, photoId, version, counter), attachmentId: UUID())
        return ledger
    }

    @Test("An empty slot uploads")
    func emptySlotUploads() {
        let ledger = SharePlayJournalLedger()

        #expect(ledger.shouldUpload(show(.photo, photoId, 3, 5), now: start))
    }

    @Test("Another item or another version of the slot's item uploads")
    func otherItemOrVersionUploads() {
        let ledger = uploaded()

        #expect(ledger.shouldUpload(show(.photo, UUID(), 3, 5), now: start))
        #expect(ledger.shouldUpload(show(.photo, photoId, 4, 5), now: start))
    }

    @Test("Each module has its own slot")
    func modulesAreIndependent() {
        let ledger = uploaded()

        #expect(ledger.shouldUpload(show(.pdf, photoId, 3, 5), now: start))
    }

    @Test("A request for the show that was already uploaded never uploads again")
    func sameShowNeverUploadsTwice() {
        let ledger = uploaded(counter: 5)
        let muchLater = start + .seconds(600)

        #expect(!ledger.shouldUpload(show(.photo, photoId, 3, 5), now: muchLater))
        #expect(!ledger.shouldUpload(show(.photo, photoId, 3, 4), now: muchLater))
    }

    @Test("A later show within a minute of the upload does not upload again")
    func laterShowWithinTheIntervalDoesNotUpload() {
        let ledger = uploaded(counter: 5)

        #expect(!ledger.shouldUpload(show(.photo, photoId, 3, 6), now: start + .seconds(59)))
        #expect(!ledger.shouldUpload(show(.photo, photoId, 3, 6), now: start + SharePlayJournalLedger.reuploadInterval))
    }

    @Test("A later show more than a minute after the upload uploads again")
    func laterShowAfterTheIntervalUploads() {
        let ledger = uploaded(counter: 5)

        #expect(ledger.shouldUpload(show(.photo, photoId, 3, 6), now: start + .seconds(61)))
    }

    @Test("The upload is reserved while it is still running")
    func runningUploadReservesTheSlot() {
        // Given: queued, not finished.
        var ledger = SharePlayJournalLedger()
        ledger.willUpload(show(.photo, photoId, 3, 5), now: start)

        // Then: a second player asking for the same show starts no second upload.
        #expect(!ledger.shouldUpload(show(.photo, photoId, 3, 5), now: start))
    }

    @Test("A failed upload frees the slot")
    func failedUploadFreesTheSlot() {
        // Given
        var ledger = SharePlayJournalLedger()
        ledger.willUpload(show(.photo, photoId, 3, 5), now: start)

        // When
        ledger.uploadFailed(show(.photo, photoId, 3, 5))

        // Then
        #expect(ledger.shouldUpload(show(.photo, photoId, 3, 5), now: start))
    }

    @Test("A failure report of an older upload does not free a newer one")
    func failureOfAnOlderUploadIsIgnored() {
        // Given
        var ledger = SharePlayJournalLedger()
        ledger.willUpload(show(.photo, photoId, 3, 5), now: start)
        ledger.willUpload(show(.photo, photoId, 4, 6), now: start)

        // When
        ledger.uploadFailed(show(.photo, photoId, 3, 5))

        // Then
        #expect(!ledger.shouldUpload(show(.photo, photoId, 4, 6), now: start))
    }

    @Test("An attachment that left the Journal can be uploaded again")
    func removedAttachmentUploadsAgain() throws {
        // Given
        var ledger = uploaded(counter: 5)
        let attachmentId = try #require(ledger.publication(in: SharePlayJournalSlot(.photo))?.attachmentId)

        // When
        ledger.didRemove(attachmentId: attachmentId)

        // Then
        #expect(ledger.shouldUpload(show(.photo, photoId, 3, 5), now: start))
    }

    @Test("A Journal snapshot without the attachment forgets it; a running upload stays reserved")
    func snapshotReconcilesPublications() {
        // Given
        var finished = uploaded(counter: 5)
        var running = SharePlayJournalLedger()
        running.willUpload(show(.photo, photoId, 3, 5), now: start)

        // When
        finished.reconcile(attachmentIds: [])
        running.reconcile(attachmentIds: [])

        // Then
        #expect(finished.shouldUpload(show(.photo, photoId, 3, 5), now: start))
        #expect(!running.shouldUpload(show(.photo, photoId, 3, 5), now: start))
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
        let attachmentId = try #require(ledger.publication(in: SharePlayJournalSlot(.photo))?.attachmentId)

        // When
        let processes = ledger.shouldProcess(attachmentId: attachmentId)

        // Then
        #expect(!processes)
    }

    @Test("A request for an item that another item pushed out of the slot does not upload it again")
    func requestForPushedOutItemDoesNotUpload() {
        // Given: an audio playlist (show 58) and then its track (show 59) took the one slot.
        let playlistId = UUID()
        let trackId = UUID()
        var ledger = SharePlayJournalLedger()
        ledger.willUpload(show(.audio, playlistId, 1, 58), now: start)
        ledger.didUpload(show(.audio, playlistId, 1, 58), attachmentId: UUID())
        ledger.willUpload(show(.audio, trackId, 1, 59), now: start)

        // Then: players that ask for the playlist while they load the track must not push the
        // track out again — the two would take the slot from each other for good.
        #expect(!ledger.shouldUpload(show(.audio, playlistId, 1, 58), now: start + .seconds(1)))
        #expect(!ledger.shouldUpload(show(.audio, playlistId, 1, 58), now: start + .seconds(600)))
        // The track keeps its slot, too.
        #expect(!ledger.shouldUpload(show(.audio, trackId, 1, 59), now: start + .seconds(1)))
    }

    @Test("A later show of a pushed-out item uploads it again")
    func laterShowOfPushedOutItemUploads() {
        // Given
        let playlistId = UUID()
        var ledger = SharePlayJournalLedger()
        ledger.willUpload(show(.audio, playlistId, 1, 58), now: start)
        ledger.willUpload(show(.audio, UUID(), 1, 59), now: start)

        // Then
        #expect(ledger.shouldUpload(show(.audio, playlistId, 1, 60), now: start))
    }

    @Test("A failed upload of the item that pushed another out leaves the pushed-out show answered")
    func pushedOutShowStaysAnsweredAfterFailure() {
        // Given
        let playlistId = UUID()
        let trackId = UUID()
        var ledger = SharePlayJournalLedger()
        ledger.willUpload(show(.audio, playlistId, 1, 58), now: start)
        ledger.willUpload(show(.audio, trackId, 1, 59), now: start)

        // When
        ledger.uploadFailed(show(.audio, trackId, 1, 59))

        // Then: the track can be tried again, the playlist's show is still not uploaded twice.
        #expect(ledger.shouldUpload(show(.audio, trackId, 1, 59), now: start))
        #expect(!ledger.shouldUpload(show(.audio, playlistId, 1, 58), now: start))
    }

    @Test("The oldest pushed-out shows are forgotten beyond the limit")
    func pushedOutShowsAreBounded() {
        // Given: many items shown one after the other.
        var ledger = SharePlayJournalLedger()
        let firstId = UUID()
        ledger.willUpload(show(.audio, firstId, 1, 1), now: start)
        for counter in 2...40 {
            ledger.willUpload(show(.audio, UUID(), 1, counter), now: start)
        }

        // Then: the first one is forgotten, so a request may upload it again.
        #expect(ledger.shouldUpload(show(.audio, firstId, 1, 1), now: start))
    }

    @Test("An audio playlist has a slot of its own: its track does not push it out")
    func playlistHasItsOwnSlot() {
        // Given: the playlist (show 58) and its first track (show 59).
        let playlistId = UUID()
        let trackId = UUID()
        var ledger = SharePlayJournalLedger()
        ledger.willUpload(show(.audio, playlistId, 1, 58, isPlaylist: true), now: start)
        ledger.willUpload(show(.audio, trackId, 1, 59), now: start)

        // Then: both stay reserved, the second upload did not displace the first.
        #expect(ledger.publication(in: SharePlayJournalSlot(.audio, isPlaylist: true))?.itemId == playlistId)
        #expect(ledger.publication(in: SharePlayJournalSlot(.audio))?.itemId == trackId)
        #expect(!ledger.shouldUpload(show(.audio, playlistId, 1, 58, isPlaylist: true), now: start))
        #expect(!ledger.shouldUpload(show(.audio, trackId, 1, 59), now: start))
    }

    @Test("A reset forgets everything")
    func reset() {
        // Given
        var ledger = uploaded()

        // When
        ledger.reset()

        // Then
        #expect(ledger.publication(in: SharePlayJournalSlot(.photo)) == nil)
        #expect(ledger.shouldUpload(show(.photo, photoId, 3, 5), now: start))
    }
}

/// The publication queue keeps one attachment per slot; an audio playlist has its own.
@Suite("SharePlay Journal slots")
@MainActor
struct SharePlayJournalSlotTests {
    struct FakeAttachment: Identifiable, Sendable {
        let id = UUID()
    }

    @Test("A playlist and a track of the audio module are both kept, a second track replaces the first")
    func playlistAndTrackKeepTheirOwnAttachment() async {
        // Given
        let queue = SharePlayJournalPublicationQueue<FakeAttachment>()
        let playlist = FakeAttachment()
        let track = FakeAttachment()
        let nextTrack = FakeAttachment()
        var removed: [UUID] = []

        func publish(_ attachment: FakeAttachment, slot: SharePlayJournalSlot) async {
            let result = queue.enqueue(
                for: slot,
                publish: { attachment },
                remove: { old in
                    removed.append(old.id)
                    return true
                }
            )
            await result.value
        }

        // When
        await publish(playlist, slot: SharePlayJournalSlot(.audio, isPlaylist: true))
        await publish(track, slot: SharePlayJournalSlot(.audio))

        // Then: the track did not replace the playlist.
        #expect(queue.currentAttachment(for: SharePlayJournalSlot(.audio, isPlaylist: true))?.id == playlist.id)
        #expect(queue.currentAttachment(for: SharePlayJournalSlot(.audio))?.id == track.id)
        #expect(removed.isEmpty)

        // When: the next track replaces the track, as before.
        await publish(nextTrack, slot: SharePlayJournalSlot(.audio))
        for _ in 0..<50 where removed.isEmpty { await Task.yield() }

        // Then
        #expect(queue.currentAttachment(for: SharePlayJournalSlot(.audio))?.id == nextTrack.id)
        #expect(queue.currentAttachment(for: SharePlayJournalSlot(.audio, isPlaylist: true))?.id == playlist.id)
        #expect(removed == [track.id])
    }
}
#endif
