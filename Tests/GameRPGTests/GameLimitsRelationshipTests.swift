// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import Foundation
import Testing

@testable import GameRPG

/// The limits of the LAN framer and of the SharePlay transports depend on each other: changing
/// one value must not silently break another.
@Suite("Game limits relationships")
struct GameLimitsRelationshipTests {
    @Test("A transport admits at least one message of the largest size")
    func everyTransportAdmitsOneLargestMessage() {
        let largest = GameLimits.maximumMessageBytes

        // Journal: takes up to the largest message, nothing more.
        #expect(GameLimits.fitsJournalAttachment(byteCount: largest))
        #expect(!GameLimits.fitsJournalAttachment(byteCount: largest + 1))
        // The inbound queue and the SharePlay budget of one sender hold at least one of them.
        #expect(GameLimits.maximumQueuedBytes >= largest)
        #expect(GameLimits.SharePlay.inboundBytesPerSender >= largest)
        // A LAN connection may queue several frames before it is dropped.
        #expect(GameLimits.maximumOutboundQueuedBytes >= largest)
    }

    @Test("Messenger carries less than the Journal and queues at least one of its largest")
    func messengerCeilingsAreConsistent() {
        #expect(GameLimits.SharePlay.messengerMessageBytes <= GameLimits.maximumMessageBytes)
        #expect(GameLimits.SharePlay.messengerOutstandingBytes >= GameLimits.SharePlay.messengerMessageBytes)
        #expect(SharePlaySingleQueuePackageSender.maxMessageByteCount == GameLimits.SharePlay.messengerMessageBytes)
        #expect(SharePlaySingleQueuePackageSender.maxOutstandingBytes == GameLimits.SharePlay.messengerOutstandingBytes)
    }

    @Test("A group event stays far below the envelope allowance of a file message")
    func groupEventsFitTheEnvelopeAllowance() {
        #expect(GameLimits.maximumGroupEventPayloadBytes <= GameLimits.envelopeAllowanceBytes)
        #expect(GameLimits.fitsOneMessage(payloadBytes: 0))
        #expect(!GameLimits.fitsOneMessage(payloadBytes: GameLimits.maximumMessageBytes))
    }

    @Test("The restart pauses never shrink, and the longest one repeats")
    func restartPausesGrow() {
        let delays = GameLimits.networkRestartDelays
        #expect(delays == delays.sorted())
        #expect(GameLimits.networkRestartDelay(forAttempt: 10_000) == delays.last)
        #expect(GameLimits.networkRestartDelay(forAttempt: -1) == delays.first)
    }

    @Test("The retry delays of attachment loads share one prefix")
    func retryDelaysShareOnePrefix() {
        let base = GameLimits.SharePlay.attachmentRetryDelays
        #expect(GameLimits.SharePlay.cleanupRetryDelays.starts(with: base))
        #expect(GameLimits.SharePlay.uploadWaitDelays.starts(with: base))
    }

    @Test("The Journal add timeout grows with the package and stays within its bounds")
    @MainActor
    func journalAddTimeoutScalesWithSize() {
        let limits = GameLimits.SharePlay.self
        #expect(limits.journalAddTimeout(forByteCount: 0) == limits.journalAddMinimumTimeout)
        #expect(limits.journalAddTimeout(forByteCount: -1) == limits.journalAddMinimumTimeout)
        // A photo keeps a short wait, a 20 MB track gets well over the old fixed 10 s.
        #expect(limits.journalAddTimeout(forByteCount: 1 * ByteUnit.megabyte) < .seconds(20))
        #expect(limits.journalAddTimeout(forByteCount: 20 * ByteUnit.megabyte) > .seconds(60))
        #expect(limits.journalAddTimeout(forByteCount: 5 * ByteUnit.megabyte) <= limits.journalAddTimeout(forByteCount: 10 * ByteUnit.megabyte))
        // The largest Journal package is capped at the long load deadline.
        #expect(limits.journalAddTimeout(forByteCount: GameLimits.maximumMessageBytes) == limits.journalAddMaximumTimeout)
        #expect(limits.journalAddMaximumTimeout == RPGSharePlayController.journalAttachmentLoadDeadline(for: .audio))
    }

    @Test("A package Messenger cannot carry always waits for its Journal add")
    func largePackagesWaitForTheJournal() {
        let limits = GameLimits.SharePlay.self
        #expect(!limits.journalWaitsInsteadOfFallback(forByteCount: 1 * ByteUnit.megabyte))
        #expect(limits.journalWaitsInsteadOfFallback(forByteCount: 15 * ByteUnit.megabyte))
        #expect(limits.journalWaitsInsteadOfFallback(forByteCount: limits.messengerMessageBytes))
        #expect(limits.journalWaitInsteadOfFallbackBytes <= limits.messengerMessageBytes)
    }

    @Test("The throttle admits a single source fewer handshakes than all sources together")
    func throttleLimitsAreConsistent() {
        #expect(GameLimits.Throttle.maximumPendingHandshakesPerSource < GameLimits.Throttle.maximumPendingHandshakes)
        #expect(GameLimits.Throttle.baseLockout <= GameLimits.Throttle.maximumLockout)
        #expect(ConnectionThrottleTracker.maximumPendingHandshakes == GameLimits.Throttle.maximumPendingHandshakes)
    }
}
#endif
