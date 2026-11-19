// @copyright André Trettin

#if canImport(Testing)
import Foundation
import Testing

@testable import GameRPG

/// CODE_AUDIT_TestGaps §3.3: the SharePlay lifecycle paths that tear a session down while
/// something is still in flight: a stop during activation, a rebind after an unbind, and a
/// cancel while a chunked payload is draining.
///
/// The coordinators are value types and the sender takes its transport as a closure, so none of
/// this needs a `GroupSession`.
@MainActor
@Suite("SharePlay lifecycle: teardown during in-flight work")
struct SharePlayLifecycleGapTests {
    // MARK: - Leave during activation

    @Test("A stop during activation, then a new activation: only the new attempt may commit")
    func stopDuringActivationThenRestart() {
        // Given: an activation is awaiting the system when the user stops sharing.
        var lifecycle = SharePlayActivationLifecycle()
        let abandonedId = UUID()
        let abandoned = lifecycle.begin(activityId: abandonedId)
        lifecycle.cancelCurrent()

        // When: sharing starts again, and the abandoned activation still reports success.
        let restartedId = UUID()
        let restarted = lifecycle.begin(activityId: restartedId)
        lifecycle.didFinish(token: abandoned, activated: true)
        lifecycle.didFinish(token: restarted, activated: true)

        // Then: the abandoned attempt cannot commit, and its session is left when it arrives.
        #expect(!lifecycle.canCommit(token: abandoned, taskIsCancelled: false))
        #expect(lifecycle.canCommit(token: restarted, taskIsCancelled: false))
        let abandonedDisposition = lifecycle.dispositionForSession(activityId: abandonedId, acceptsSessions: true)
        let restartedDisposition = lifecycle.dispositionForSession(activityId: restartedId, acceptsSessions: true)
        #expect(abandonedDisposition == .leave)
        #expect(restartedDisposition == .configure)
        #expect(!lifecycle.hasObsoleteActivities)
    }

    @Test("An activation that failed leaves nothing behind that rejects a later session")
    func failedActivationLeavesNoObsoleteEntry() {
        var lifecycle = SharePlayActivationLifecycle()
        let token = lifecycle.begin(activityId: UUID())

        lifecycle.didFinish(token: token, activated: false)

        #expect(!lifecycle.hasObsoleteActivities)
        // An unrelated session (another device started SharePlay) is still admitted ...
        let admitted = lifecycle.dispositionForSession(activityId: nil, acceptsSessions: true)
        #expect(admitted == .configure)
        // ... and a cleanup-only observer has no obsolete activity to wait for.
        let cleanedUp = lifecycle.dispositionForSession(activityId: nil, acceptsSessions: false)
        #expect(cleanedUp == .leaveAndStopCleanup)
    }

    @Test("A stopped activation keeps the cleanup observer until its session has been left")
    func cleanupObserverWaitsForTheObsoleteSession() {
        var lifecycle = SharePlayActivationLifecycle()
        let obsoleteId = UUID()
        _ = lifecycle.begin(activityId: obsoleteId)
        lifecycle.cancelCurrent()

        // A session from somewhere else must not end the cleanup while the obsolete one is due.
        let foreign = lifecycle.dispositionForSession(activityId: UUID(), acceptsSessions: false)
        #expect(foreign == .leave)
        #expect(lifecycle.hasObsoleteActivities)

        // The obsolete session arrives: it is left, and the cleanup observer can stop.
        let obsolete = lifecycle.dispositionForSession(activityId: obsoleteId, acceptsSessions: false)
        #expect(obsolete == .leaveAndStopCleanup)
        #expect(!lifecycle.hasObsoleteActivities)
    }

    // MARK: - Rebind after unbind

    @Test("A session observer started again after a stop revokes the one before it")
    func observerRebindRevokesTheOldGeneration() {
        var lifecycle = SharePlaySessionObserverLifecycle()
        let first = lifecycle.start(acceptsSessions: true)

        lifecycle.stop()
        let second = lifecycle.start(acceptsSessions: true)

        #expect(!lifecycle.isCurrent(token: first, taskIsCancelled: false))
        #expect(!lifecycle.canConfigure(token: first, taskIsCancelled: false))
        #expect(lifecycle.canConfigure(token: second, taskIsCancelled: false))
        // A cancelled observer task never configures, whatever its generation.
        #expect(!lifecycle.canConfigure(token: second, taskIsCancelled: true))

        // Stopping twice leaves it stopped, not accepting.
        lifecycle.stop()
        lifecycle.stop()
        #expect(!lifecycle.acceptsSessions)
        #expect(!lifecycle.canConfigure(token: second, taskIsCancelled: false))
    }

    @Test("The same session id bound again after a reset must request its join again")
    func sessionRebindNeedsANewJoinRequest() {
        let sessionId = UUID()
        var lifecycle = SharePlaySessionLifecycle()
        lifecycle.prepare(sessionId: sessionId)
        lifecycle.didRequestJoin(sessionId: sessionId)
        let configured = lifecycle.didEnterJoinedState(sessionId: sessionId)
        #expect(configured)

        // The session is unbound (reset) while its joined callback may still be on its way.
        lifecycle.reset()
        #expect(!lifecycle.isCurrent(sessionId: sessionId))
        let configuredAfterReset = lifecycle.didEnterJoinedState(sessionId: sessionId)
        #expect(!configuredAfterReset)

        // Bound again: the old join request and the old configuration are gone.
        lifecycle.prepare(sessionId: sessionId)
        let configuredWithoutJoin = lifecycle.didEnterJoinedState(sessionId: sessionId)
        #expect(!configuredWithoutJoin)
        lifecycle.didRequestJoin(sessionId: sessionId)
        let configuredAfterRejoin = lifecycle.didEnterJoinedState(sessionId: sessionId)
        let configuredTwice = lifecycle.didEnterJoinedState(sessionId: sessionId)
        #expect(configuredAfterRejoin)
        #expect(!configuredTwice)
    }

    @Test("An operation of the unbound session cannot commit into the session bound after it")
    func operationTokenDoesNotSurviveARebind() {
        let sessionId = UUID()
        var lifecycle = SharePlaySessionLifecycle()
        lifecycle.prepare(sessionId: sessionId)
        let token = SharePlaySessionOperationToken(sessionId: sessionId, generation: 1)
        #expect(token.canCommit(lifecycle: lifecycle, currentGeneration: 1, taskIsCancelled: false))

        lifecycle.reset()
        lifecycle.prepare(sessionId: sessionId)

        // The session id is the same again, but the transport generation moved on.
        #expect(!token.canCommit(lifecycle: lifecycle, currentGeneration: 2, taskIsCancelled: false))
        #expect(token.canCommit(lifecycle: lifecycle, currentGeneration: 1, taskIsCancelled: false))
        #expect(!token.canCommit(lifecycle: lifecycle, currentGeneration: 1, taskIsCancelled: true))
    }

    @Test("The controller can join again after it stopped joining")
    func controllerJoinsAgainAfterStopJoin() {
        let controller = RPGSharePlayController()

        controller.joinGame()
        #expect(controller.connectionState == .waiting)
        controller.stopJoin()
        #expect(controller.connectionState == .inactive)

        controller.joinGame()
        #expect(controller.connectionState == .waiting)

        controller.stopJoin()
        #expect(controller.connectionState == .inactive)
    }

    // MARK: - Cancel while a chunked send drains

    @Test("Stopping the sender while a payload drains sends no further package and fails every caller")
    func cancelAllWhileDraining() async throws {
        // Given: a four-package payload whose first package is still being sent, and a second
        // payload queued behind it.
        let transport = BlockedTransport()
        let sender = SharePlaySingleQueuePackageSender(packageSize: 4, retryDelays: []) { package in
            await transport.send(package)
        }
        let draining = Task { try await sender.send(data: Data(count: 16)) }
        let queued = Task { try await sender.send(data: Data(count: 4)) }
        #expect(await awaitCondition { await transport.sentCount == 1 })

        // When: the session ends.
        sender.cancelAll()
        await transport.release()

        // Then: both callers are failed, nothing more is sent, and the sender stays stopped.
        await #expect(throws: CancellationError.self) { try await draining.value }
        await #expect(throws: CancellationError.self) { try await queued.value }
        #expect(await conditionHolds { await transport.sentCount == 1 })
        await #expect(throws: SharePlayPackageSenderError.senderStopped) {
            try await sender.send(data: Data(count: 4))
        }
    }

    @Test("A caller that is cancelled mid-drain loses its remaining packages, not the next payload")
    func cancelledCallerDoesNotBlockTheNextPayload() async throws {
        // Given: payload A (four packages) is draining and payload B (two packages) waits.
        let transport = BlockedTransport()
        let sender = SharePlaySingleQueuePackageSender(packageSize: 4, retryDelays: []) { package in
            await transport.send(package)
        }
        let first = Task { try await sender.send(data: Data(count: 16)) }
        let second = Task { try await sender.send(data: Data(count: 8)) }
        #expect(await awaitCondition { await transport.sentCount == 1 })
        let streamOfFirst = try #require(await transport.packages.first?.uuid)

        // When: the caller of A is cancelled while its first package is on the wire.
        first.cancel()
        await #expect(throws: CancellationError.self) { try await first.value }
        await transport.release()

        // Then: B is sent whole, in order, and no more of A follows its first package.
        try await second.value
        let packages = await transport.packages
        #expect(packages.count == 3)
        #expect(packages.filter { $0.uuid == streamOfFirst }.count == 1)
        let secondPackages = packages.filter { $0.uuid != streamOfFirst }
        #expect(secondPackages.map(\.count) == [1, 2])
        #expect(secondPackages.allSatisfy { $0.total == 2 })
    }
}

/// A transport whose first package stays on the wire until the test releases it.
private actor BlockedTransport {
    private(set) var packages: [PackageMessage] = []
    private var blocked: CheckedContinuation<Void, Never>?
    private var isReleased = false

    var sentCount: Int { packages.count }

    func send(_ package: PackageMessage) async {
        packages.append(package)
        guard packages.count == 1, !isReleased else { return }
        await withCheckedContinuation { blocked = $0 }
    }

    func release() {
        isReleased = true
        blocked?.resume()
        blocked = nil
    }
}
#endif
