// @copyright André Trettin

#if !os(tvOS)
import AppIntents
import Foundation
import Testing

@testable import CoreRPG

/// CODE_AUDIT_TestGaps §5.9: the throttle that keeps a combat round from flooding the system's
/// donations. The donation itself goes to the system and is only logged when it is refused.
@Suite("Intent donations", .serialized)
@MainActor
struct IntentDonationsTests {
    struct DonationProbeIntent: AppIntent {
        static let title: LocalizedStringResource = "Donation Probe"
        func perform() async throws -> some IntentResult { .result() }
    }

    @Test("The same item is donated once within the repeat interval")
    func throttledDonationOncePerItem() async {
        let itemId = UUID()
        var made = 0

        await IntentDonations.donateThrottled(for: itemId) { made += 1; return DonationProbeIntent() }
        await IntentDonations.donateThrottled(for: itemId) { made += 1; return DonationProbeIntent() }
        await IntentDonations.donateThrottled(for: itemId) { made += 1; return DonationProbeIntent() }

        #expect(made == 1)
    }

    @Test("Different items are throttled independently")
    func differentItemsAreIndependent() async {
        var made = 0

        await IntentDonations.donateThrottled(for: UUID()) { made += 1; return DonationProbeIntent() }
        await IntentDonations.donateThrottled(for: UUID()) { made += 1; return DonationProbeIntent() }

        #expect(made == 2)
    }

    @Test("An item that is gone donates nothing and is not throttled afterwards")
    func missingIntentIsNotRecorded() async {
        let itemId = UUID()
        var attempts = 0
        var delivered = 0

        await IntentDonations.donateThrottled(for: itemId) { attempts += 1; return nil }
        await IntentDonations.donateThrottled(for: itemId) { attempts += 1; delivered += 1; return DonationProbeIntent() }

        #expect(attempts == 2, "the nil answer did not start the throttle")
        #expect(delivered == 1)
    }

    @Test("An open is not donated when the selection changes during the dwell")
    func openIsNotDonatedWhenCancelled() async {
        var made = 0
        let task = Task { await IntentDonations.donateOpen(of: UUID()) { made += 1; return DonationProbeIntent() } }

        task.cancel()
        await task.value

        #expect(made == 0)
    }
}
#endif
