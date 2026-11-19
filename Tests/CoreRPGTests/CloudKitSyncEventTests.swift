// @copyright André Trettin

#if canImport(Testing)
import Foundation
import Testing

@testable import CoreRPG

/// CODE_AUDIT_TestGaps §5.2: the sync state drives what the user is told about iCloud, so a
/// failed sync must never be shown as a good one.
@MainActor
@Suite("CloudKit sync events")
struct CloudKitSyncEventTests {
    private struct SyncFailure: LocalizedError {
        let errorDescription: String? = "iCloud storage is full"
    }

    private let now = Date(timeIntervalSince1970: 1_000)

    private func model() -> CoreDataInitModel {
        CoreDataInitModel(inMemory: true, currentActor: .mainApp)
    }

    // MARK: - Event → update

    @Test("A successful setup changes nothing")
    func setupSucceeded() {
        let update = CloudKitSyncEvent(kind: .setup, succeeded: true).modelUpdate(now: now)

        #expect(update == .none)
    }

    @Test("A setup without a result is in progress")
    func setupRunning() {
        let update = CloudKitSyncEvent(kind: .setup, succeeded: false).modelUpdate(now: now)

        #expect(update == .syncState(.inProgress))
    }

    @Test("A failed setup is surfaced with the reason, not masked as in progress")
    func setupFailed() {
        let update = CloudKitSyncEvent(kind: .setup, succeeded: false, error: SyncFailure()).modelUpdate(now: now)

        #expect(update == .syncState(.failed("iCloud storage is full")))
    }

    @Test("A successful import and export record the time")
    func importAndExportSucceeded() {
        let imported = CloudKitSyncEvent(kind: .import, succeeded: true).modelUpdate(now: now)
        let exported = CloudKitSyncEvent(kind: .export, succeeded: true).modelUpdate(now: now)

        #expect(imported == .importSucceeded(now))
        #expect(exported == .exportSucceeded(now))
    }

    @Test("A failed import or export is surfaced with the reason", arguments: [CloudKitSyncEvent.Kind.import, .export])
    func transferFailed(kind: CloudKitSyncEvent.Kind) {
        let update = CloudKitSyncEvent(kind: kind, succeeded: false, error: SyncFailure()).modelUpdate(now: now)

        #expect(update == .syncState(.failed("iCloud storage is full")))
    }

    @Test("An import or export without a result is in progress", arguments: [CloudKitSyncEvent.Kind.import, .export])
    func transferRunning(kind: CloudKitSyncEvent.Kind) {
        let update = CloudKitSyncEvent(kind: kind, succeeded: false).modelUpdate(now: now)

        #expect(update == .syncState(.inProgress))
    }

    @Test("A success wins over a stale error on the same event", arguments: [CloudKitSyncEvent.Kind.import, .export])
    func successIgnoresError(kind: CloudKitSyncEvent.Kind) {
        let update = CloudKitSyncEvent(kind: kind, succeeded: true, error: SyncFailure()).modelUpdate(now: now)

        #expect(update != .syncState(.failed("iCloud storage is full")))
    }

    @Test("An event type from a newer SDK changes nothing")
    func unknownEvent() {
        let update = CloudKitSyncEvent(kind: .unknown, succeeded: false, error: SyncFailure()).modelUpdate(now: now)

        #expect(update == .none)
    }

    // MARK: - Update → model

    @Test("A new model has not started syncing")
    func initialState() {
        let model = model()

        #expect(model.cloudKitSyncState == .notStarted)
        #expect(model.lastSuccessfulSync == nil)
    }

    @Test("An import or export success clears a failure and stamps the time", arguments: [true, false])
    func successClearsFailure(isImport: Bool) {
        let model = model()
        model.apply(.syncState(.failed("offline")))
        #expect(model.cloudKitSyncState == .failed("offline"))

        model.apply(isImport ? .importSucceeded(now) : .exportSucceeded(now))

        #expect(model.cloudKitSyncState == .succeeded)
        #expect(model.lastSuccessfulSync == now)
    }

    @Test("A failure after a success keeps the time of the last success")
    func failureKeepsLastSuccess() {
        let model = model()
        model.apply(.importSucceeded(now))

        model.apply(.syncState(.failed("offline")))

        #expect(model.cloudKitSyncState == .failed("offline"))
        #expect(model.lastSuccessfulSync == now)
    }

    @Test("An update of .none leaves the state alone")
    func noneLeavesTheState() {
        let model = model()
        model.apply(.syncState(.failed("offline")))

        model.apply(.none)

        #expect(model.cloudKitSyncState == .failed("offline"))
    }

    @Test("A sequence of events ends in the state of the last one")
    func sequence() {
        let model = model()
        let events: [CloudKitSyncEvent] = [
            CloudKitSyncEvent(kind: .setup, succeeded: false),
            CloudKitSyncEvent(kind: .setup, succeeded: true),
            CloudKitSyncEvent(kind: .import, succeeded: false),
            CloudKitSyncEvent(kind: .import, succeeded: true),
            CloudKitSyncEvent(kind: .export, succeeded: false, error: SyncFailure())
        ]

        for event in events { model.apply(event.modelUpdate(now: now)) }

        // The export failed last: the UI must not keep showing the import's success.
        #expect(model.cloudKitSyncState == .failed("iCloud storage is full"))
        #expect(model.lastSuccessfulSync == now)
    }
}
#endif
