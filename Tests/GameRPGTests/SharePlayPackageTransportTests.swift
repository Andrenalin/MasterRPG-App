// @copyright André Trettin

#if canImport(Testing)
import Foundation
import Testing

@testable import CoreRPG
@testable import GameRPG

@Suite("SharePlay package transport")
@MainActor
struct SharePlayPackageTransportTests {

    @Test("participants present before join replay once after the session joins")
    func participantsPresentBeforeJoinReplayOnce() {
        // Given
        let localParticipantId = UUID()
        let firstRemoteParticipantId = UUID()
        let secondRemoteParticipantId = UUID()
        let activeParticipantIds: Set<UUID> = [
            localParticipantId,
            firstRemoteParticipantId,
            secondRemoteParticipantId
        ]
        var tracker = SharePlayParticipantTracker()

        // When - GroupActivities publishes its initial roster before `.joined`.
        let waitingChange = tracker.participantsChanged(
            activeParticipantIds: activeParticipantIds,
            localParticipantId: localParticipantId,
            sessionIsJoined: false
        )
        let joinedParticipants = tracker.sessionDidJoin(
            activeParticipantIds: activeParticipantIds,
            localParticipantId: localParticipantId
        )
        let repeatedChange = tracker.participantsChanged(
            activeParticipantIds: activeParticipantIds,
            localParticipantId: localParticipantId,
            sessionIsJoined: true
        )

        // Then
        #expect(waitingChange.added.isEmpty)
        #expect(waitingChange.removed.isEmpty)
        #expect(joinedParticipants == [firstRemoteParticipantId, secondRemoteParticipantId])
        #expect(!joinedParticipants.contains(localParticipantId))
        #expect(repeatedChange.added.isEmpty)
        #expect(repeatedChange.removed.isEmpty)
    }

    @Test("a participant that leaves and rejoins receives a fresh replay")
    func rejoinedParticipantReceivesFreshReplay() {
        // Given
        let localParticipantId = UUID()
        let remoteParticipantId = UUID()
        var tracker = SharePlayParticipantTracker()
        _ = tracker.sessionDidJoin(
            activeParticipantIds: [localParticipantId, remoteParticipantId],
            localParticipantId: localParticipantId
        )

        // When
        let removed = tracker.participantsChanged(
            activeParticipantIds: [localParticipantId],
            localParticipantId: localParticipantId,
            sessionIsJoined: true
        )
        let readded = tracker.participantsChanged(
            activeParticipantIds: [localParticipantId, remoteParticipantId],
            localParticipantId: localParticipantId,
            sessionIsJoined: true
        )

        // Then
        #expect(removed.removed == [remoteParticipantId])
        #expect(removed.added.isEmpty)
        #expect(readded.added == [remoteParticipantId])
        #expect(readded.removed.isEmpty)
    }

    @Test("session replacement drains old participants before the connection reset")
    func sessionReplacementDrainsOldParticipantsInOrder() throws {
        // Given
        let localParticipantId = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let firstRemoteParticipantId = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        let secondRemoteParticipantId = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000003"))
        var tracker = SharePlayParticipantTracker()
        _ = tracker.sessionDidJoin(
            activeParticipantIds: [
                secondRemoteParticipantId,
                localParticipantId,
                firstRemoteParticipantId
            ],
            localParticipantId: localParticipantId
        )

        // When
        let firstTeardown = tracker.drainSessionTeardownEvents()
        let repeatedTeardown = tracker.drainSessionTeardownEvents()
        let staleRosterChange = tracker.participantsChanged(
            activeParticipantIds: [localParticipantId],
            localParticipantId: localParticipantId,
            sessionIsJoined: true
        )

        // Then - participant-specific cleanup is deterministic and completes
        // before the full lost-connection reset. Draining prevents duplicates
        // if the old roster emits an empty snapshot while cancellation settles.
        #expect(firstTeardown == [
            .lostParticipant(firstRemoteParticipantId),
            .lostParticipant(secondRemoteParticipantId),
            .lostConnection
        ])
        #expect(repeatedTeardown == [.lostConnection])
        #expect(staleRosterChange.removed.isEmpty)
    }

    @Test("session teardown awaits delegate cleanup in event order")
    func sessionTeardownAwaitsDelegateCleanupInOrder() async {
        // Given
        let firstParticipantId = UUID()
        let secondParticipantId = UUID()
        let controller = RPGSharePlayController()
        let delegate = SharePlayTeardownDelegateRecorder()
        controller.delegate = delegate

        // When
        await controller.reportSessionTeardown([
            .lostParticipant(firstParticipantId),
            .lostParticipant(secondParticipantId),
            .lostConnection
        ])

        // Then - returning from the report means every old-session reset has
        // completed; configureGroupSession can now safely create its new loops.
        #expect(delegate.events == [
            .lostParticipant(firstParticipantId),
            .lostParticipant(secondParticipantId),
            .lostConnection
        ])
        controller.delegate = nil
        controller.reset()
    }

    @Test("session replacement during configured callback stops old-session replay")
    func replacementDuringConfiguredCallbackStopsOldSession() async {
        // Given
        let oldSessionId = UUID()
        let replacementSessionId = UUID()
        let participantId = UUID()
        let lifecycle = SharePlaySessionLifecycleHarness(sessionId: oldSessionId)
        let callbackCoordinator = SharePlaySessionCallbackCoordinator()
        let delegate = SuspendedSharePlayDelegateRecorder(suspending: .configured)
        let oldSessionLoop = Task { @MainActor in
            guard await callbackCoordinator.perform(
                sessionId: oldSessionId,
                shouldContinue: { lifecycle.isCurrent(sessionId: oldSessionId) },
                operation: { await delegate.sharePlaySessionConfigured() }
            ) else { return }

            delegate.record(.postCallbackMutation)
            guard await callbackCoordinator.perform(
                sessionId: oldSessionId,
                shouldContinue: { lifecycle.isCurrent(sessionId: oldSessionId) },
                operation: { await delegate.sharePlayJoinedPlayer(id: participantId) }
            ) else { return }
        }
        await delegate.waitUntilSuspended()

        // When - sessions() configures a replacement while ready() is
        // suspended reporting the player's availability lists.
        lifecycle.prepare(sessionId: replacementSessionId)
        delegate.resumeSuspendedCallback()
        await oldSessionLoop.value

        // Then - the callback may finish, but the old state loop cannot mutate
        // its tracker or replay a participant into the replacement session.
        #expect(delegate.events == [.configured])
    }

    @Test("session invalidation during lost-player callback stops remaining old callbacks")
    func invalidationDuringLostPlayerCallbackStopsOldParticipantLoop() async throws {
        // Given
        let sessionId = UUID()
        let firstParticipantId = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000011"))
        let secondParticipantId = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000012"))
        let joinedParticipantId = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000013"))
        let lifecycle = SharePlaySessionLifecycleHarness(sessionId: sessionId)
        let callbackCoordinator = SharePlaySessionCallbackCoordinator()
        let delegate = SuspendedSharePlayDelegateRecorder(
            suspending: .lostParticipant(firstParticipantId)
        )
        let oldParticipantLoop = Task { @MainActor in
            for participantId in [firstParticipantId, secondParticipantId] {
                guard await callbackCoordinator.perform(
                    sessionId: sessionId,
                    shouldContinue: { lifecycle.isCurrent(sessionId: sessionId) },
                    operation: { await delegate.sharePlayLostPlayer(id: participantId) }
                ) else { return }
            }
            guard await callbackCoordinator.perform(
                sessionId: sessionId,
                shouldContinue: { lifecycle.isCurrent(sessionId: sessionId) },
                operation: { await delegate.sharePlayJoinedPlayer(id: joinedParticipantId) }
            ) else { return }
        }
        await delegate.waitUntilSuspended()

        // When - reset both invalidates the lifecycle and cancels its worker.
        lifecycle.reset()
        oldParticipantLoop.cancel()
        delegate.resumeSuspendedCallback()
        await oldParticipantLoop.value

        // Then
        #expect(delegate.events == [.lostParticipant(firstParticipantId)])
    }

    @Test("replacement configuration waits for suspended invalidation teardown")
    func replacementWaitsForSuspendedInvalidationTeardown() async {
        // Given
        let coordinator = SharePlaySessionTeardownCoordinator()
        let delegate = SuspendedSharePlayDelegateRecorder(suspending: .lostConnection)
        let invalidation = Task { @MainActor in
            let teardown = coordinator.start {
                await delegate.sharePlayLostConnection()
            }
            await coordinator.waitForCompletion(of: teardown)
        }
        await delegate.waitUntilSuspended()

        // When - a replacement attempts configuration while the invalidation
        // delegate is still suspended.
        let replacement = Task { @MainActor in
            delegate.record(.replacementConfigurationAttempted)
            await coordinator.waitForPendingTeardown()
            delegate.record(.replacementConfigured)
        }
        await delegate.waitUntilRecorded(.replacementConfigurationAttempted)

        // Then - configuration remains behind the registered teardown token.
        #expect(delegate.events == [
            .lostConnection,
            .replacementConfigurationAttempted
        ])
        delegate.resumeSuspendedCallback()
        await invalidation.value
        await replacement.value
        #expect(delegate.events == [
            .lostConnection,
            .replacementConfigurationAttempted,
            .replacementConfigured
        ])
    }

    @Test("stopped delayed activation cannot commit and its session is rejected")
    func stoppedDelayedActivationIsRejected() {
        // Given
        let activityId = UUID()
        var lifecycle = SharePlayActivationLifecycle()
        let token = lifecycle.begin(activityId: activityId)

        // When - stop happens while the system activation is suspended, but
        // the non-cooperative operation still reports success afterward.
        lifecycle.cancelCurrent()
        let canCommit = lifecycle.canCommit(token: token, taskIsCancelled: true)
        lifecycle.didFinish(token: token, activated: true)

        // Then - its exactly tagged GroupSession is left and closes the bounded
        // cleanup subscriber; unrelated sessions remain admissible after restart.
        #expect(!canCommit)
        #expect(lifecycle.hasObsoleteActivities)
        #expect(lifecycle.dispositionForSession(
            activityId: activityId,
            acceptsSessions: false
        ) == .leaveAndStopCleanup)
        #expect(!lifecycle.hasObsoleteActivities)
        #expect(lifecycle.dispositionForSession(
            activityId: UUID(),
            acceptsSessions: true
        ) == .configure)
    }

    @Test("stop invalidates admitted configuration and cleanup observer only leaves")
    func stopInvalidatesAdmittedConfigurationBeforeCleanupObserver() {
        // Given - the normal observer has admitted a session just before its
        // configure operation suspends.
        var observerLifecycle = SharePlaySessionObserverLifecycle()
        let normalToken = observerLifecycle.start(acceptsSessions: true)
        #expect(observerLifecycle.canConfigure(
            token: normalToken,
            taskIsCancelled: false
        ))

        // When - stop revokes that generation and creates a fresh cleanup-only
        // observer for a delayed successful activation.
        observerLifecycle.stop()
        let cleanupToken = observerLifecycle.start(acceptsSessions: false)
        var activationLifecycle = SharePlayActivationLifecycle()
        let activityId = UUID()
        _ = activationLifecycle.begin(activityId: activityId)
        activationLifecycle.cancelCurrent()

        // Then - resuming the old configure cannot commit, while the current
        // cleanup observer is valid but has no path that configures a session.
        #expect(!observerLifecycle.canConfigure(
            token: normalToken,
            taskIsCancelled: false
        ))
        #expect(observerLifecycle.isCurrent(
            token: cleanupToken,
            taskIsCancelled: false
        ))
        #expect(!observerLifecycle.canConfigure(
            token: cleanupToken,
            taskIsCancelled: false
        ))
        #expect(activationLifecycle.dispositionForSession(
            activityId: activityId,
            acceptsSessions: observerLifecycle.acceptsSessions
        ) == .leaveAndStopCleanup)
    }

    @Test("restarted activation rejects only the obsolete attempt")
    func restartedActivationRejectsOnlyObsoleteAttempt() {
        // Given
        let firstActivityId = UUID()
        let replacementActivityId = UUID()
        var lifecycle = SharePlayActivationLifecycle()
        let firstToken = lifecycle.begin(activityId: firstActivityId)

        // When
        let replacementToken = lifecycle.begin(activityId: replacementActivityId)
        lifecycle.didFinish(token: firstToken, activated: true)
        lifecycle.didFinish(token: replacementToken, activated: true)

        // Then
        #expect(!lifecycle.canCommit(token: firstToken, taskIsCancelled: false))
        #expect(lifecycle.canCommit(token: replacementToken, taskIsCancelled: false))
        #expect(lifecycle.dispositionForSession(
            activityId: firstActivityId,
            acceptsSessions: true
        ) == .leave)
        #expect(lifecycle.dispositionForSession(
            activityId: replacementActivityId,
            acceptsSessions: true
        ) == .configure)
    }

    @Test("sender reports the correct total for exact-size chunks")
    func senderReportsCorrectTotalForExactSizeChunks() async throws {
        let data = Data("abcdefgh".utf8)
        let collector = PackageCollector()
        let sender = SharePlaySingleQueuePackageSender(packageSize: 4) { package in
            await collector.append(package)
        }

        try await sender.send(data: data)

        let packages = await collector.values
        #expect(sender.packageCount(for: data) == 2)
        #expect(packages.count == 2)
        #expect(packages.map(\.count) == [1, 2])
        #expect(packages.map(\.total) == [2, 2])
        #expect(packages.compactMap(\.data).reduce(Data(), +) == data)
    }

    @Test("default chunks remain below the encoded messenger limit")
    func defaultChunksRemainBelowEncodedMessengerLimit() async throws {
        let data = Data(repeating: 0xFF, count: SharePlaySingleQueuePackageSender.packageSize)
        let collector = PackageCollector()
        let sender = SharePlaySingleQueuePackageSender { package in
            await collector.append(package)
        }

        try await sender.send(data: data)

        let packages = await collector.values
        let package = try #require(packages.first)
        let encodedSize = try JSONEncoder().encode(package).count
        #expect(packages.count == 1)
        #expect(encodedSize < SharePlaySingleQueuePackageSender.encodedMessageSizeLimit)
    }

    @Test("sender retries a transient package failure")
    func senderRetriesTransientPackageFailure() async throws {
        let probe = PackageSendRetryProbe(failuresRemaining: 2)
        let sender = SharePlaySingleQueuePackageSender(
            packageSize: 4,
            retryDelays: [.zero, .zero]
        ) { package in
            try await probe.send(package)
        }

        try await sender.send(data: Data("abcd".utf8))

        #expect(await probe.attemptCount == 3)
        #expect(await probe.sentPackageCount == 1)
    }

    @Test("sender physically targets every package in a participant stream")
    func senderTargetsEveryPackageInParticipantStream() async throws {
        // Given
        let participantId = UUID()
        let collector = TargetedPackageCollector()
        let sender = SharePlaySingleQueuePackageSender(packageSize: 4) { package, targetId in
            await collector.append(package, participantId: targetId)
        }

        // When
        try await sender.send(data: Data("abcdefgh".utf8), participantId: participantId)

        // Then
        let deliveries = await collector.values
        #expect(deliveries.map(\.package.count) == [1, 2])
        #expect(deliveries.map(\.participantId) == [participantId, participantId])
    }

    @Test("concurrent sends keep every whole message in FIFO order")
    func concurrentSendsKeepWholeMessagesInFIFOOrder() async throws {
        // Given
        let gate = PackageSendGate()
        let sender = SharePlaySingleQueuePackageSender(packageSize: 4) { package in
            await gate.send(package)
        }
        let firstSend = Task {
            try await sender.send(data: Data("abcdefgh".utf8))
        }
        await gate.waitUntilFirstPackageIsSending()

        // When
        let secondSend = Task {
            try await sender.send(data: Data("ijklmnop".utf8))
        }
        await Task.yield()
        await gate.resumeFirstPackage()
        try await firstSend.value
        try await secondSend.value

        // Then
        let packages = await gate.packages
        let streamIds = packages.map(\.uuid)
        #expect(packages.map(\.count) == [1, 2, 1, 2])
        #expect(streamIds[0] == streamIds[1])
        #expect(streamIds[2] == streamIds[3])
        #expect(streamIds[0] != streamIds[2])
    }

    @Test("sender rejects work beyond its bounded whole-message queue")
    func senderRejectsWorkBeyondBoundedQueue() async throws {
        // Given
        let gate = PackageSendGate()
        let sender = SharePlaySingleQueuePackageSender(
            packageSize: 4,
            maxOutstandingMessages: 1,
            maxOutstandingBytes: 16,
            maxMessageByteCount: 8
        ) { package in
            await gate.send(package)
        }
        let activeSend = Task {
            try await sender.send(data: Data("abcdefgh".utf8))
        }
        await gate.waitUntilFirstPackageIsSending()

        // When / Then
        await #expect(throws: SharePlayPackageSenderError.queueFull) {
            try await sender.send(data: Data("ijkl".utf8))
        }

        await gate.resumeFirstPackage()
        try await activeSend.value
    }

    @Test("receiver reassembles packages by package number")
    func receiverReassemblesPackagesByPackageNumber() {
        let id = UUID()
        let receiver = SharePlayPackageReceiver()
        let first = PackageMessage(uuid: id, count: 1, total: 2, data: Data("abcd".utf8))
        let second = PackageMessage(uuid: id, count: 2, total: 2, data: Data("efgh".utf8))

        #expect(receiver.received(
            package: second,
            from: Self.packageSourceParticipantId
        ) == nil)
        let result = receiver.received(
            package: first,
            from: Self.packageSourceParticipantId
        )?.reassembledData()

        #expect(result == Data("abcdefgh".utf8))
    }

    @Test("receiver isolates identical stream IDs by source participant")
    func receiverIsolatesIdenticalStreamIdsByParticipant() throws {
        // Given - every SharePlay participant sees package UUIDs from every
        // sender, so a UUID alone is not a transport identity.
        let streamId = UUID()
        let firstParticipantId = UUID()
        let secondParticipantId = UUID()
        let receiver = SharePlayPackageReceiver()

        // When - two participants interleave the same stream UUID.
        #expect(receiver.received(
            package: PackageMessage(
                uuid: streamId,
                count: 1,
                total: 2,
                data: Data("first-1".utf8)
            ),
            from: firstParticipantId
        ) == nil)
        #expect(receiver.received(
            package: PackageMessage(
                uuid: streamId,
                count: 2,
                total: 2,
                data: Data("second-2".utf8)
            ),
            from: secondParticipantId
        ) == nil)
        let second = try #require(receiver.received(
            package: PackageMessage(
                uuid: streamId,
                count: 1,
                total: 2,
                data: Data("second-1".utf8)
            ),
            from: secondParticipantId
        ))
        let first = try #require(receiver.received(
            package: PackageMessage(
                uuid: streamId,
                count: 2,
                total: 2,
                data: Data("first-2".utf8)
            ),
            from: firstParticipantId
        ))

        // Then - neither payload contains chunks from the other participant,
        // and completion retains the physical source used for authorization.
        #expect(second.sourceParticipantId == secondParticipantId)
        #expect(second.reassembledData() == Data("second-1second-2".utf8))
        #expect(first.sourceParticipantId == firstParticipantId)
        #expect(first.reassembledData() == Data("first-1first-2".utf8))
    }

    @Test("receiver rejects oversized packages and streams")
    func receiverRejectsOversizedPackagesAndStreams() {
        // Given
        let receiver = SharePlayPackageReceiver(
            maxPackagesPerStream: 3,
            maxPackageByteCount: 4,
            maxStreamByteCount: 6,
            maxCumulativeByteCount: 12
        )
        let oversizedPackageId = UUID()
        let oversizedStreamId = UUID()

        // When
        let oversizedPackage = receiver.received(package: PackageMessage(
            uuid: oversizedPackageId,
            count: 1,
            total: 2,
            data: Data("12345".utf8)
        ), from: Self.packageSourceParticipantId)
        _ = receiver.received(package: PackageMessage(
            uuid: oversizedStreamId,
            count: 1,
            total: 2,
            data: Data("1234".utf8)
        ), from: Self.packageSourceParticipantId)
        let oversizedStream = receiver.received(package: PackageMessage(
            uuid: oversizedStreamId,
            count: 2,
            total: 2,
            data: Data("5678".utf8)
        ), from: Self.packageSourceParticipantId)

        // Then
        #expect(oversizedPackage == nil)
        #expect(oversizedStream == nil)
        #expect(receiver.receivedPackages[Self.streamKey(oversizedPackageId)] == nil)
        #expect(receiver.receivedPackages[Self.streamKey(oversizedStreamId)]?.packageCounter == 1)
        #expect(receiver.cumulativeIncompleteByteCount == 4)
    }

    @Test("receiver bounds cumulative incomplete bytes by evicting old streams")
    func receiverBoundsCumulativeIncompleteBytes() {
        // Given
        let firstId = UUID()
        let secondId = UUID()
        let thirdId = UUID()
        let receiver = SharePlayPackageReceiver(
            maxIncompleteStreams: 4,
            maxPackagesPerStream: 3,
            maxPackageByteCount: 4,
            maxStreamByteCount: 8,
            maxCumulativeByteCount: 8
        )
        _ = receiver.received(
            package: Self.incompletePackage(id: firstId, count: 1, data: "1111"),
            from: Self.packageSourceParticipantId
        )
        _ = receiver.received(
            package: Self.incompletePackage(id: secondId, count: 1, data: "2222"),
            from: Self.packageSourceParticipantId
        )

        // When
        _ = receiver.received(
            package: Self.incompletePackage(id: thirdId, count: 1, data: "3333"),
            from: Self.packageSourceParticipantId
        )

        // Then
        #expect(Set(receiver.receivedPackages.keys.map(\.packageId)) == [secondId, thirdId])
        #expect(receiver.cumulativeIncompleteByteCount == 8)
    }

    @Test("duplicate chunks do not extend incomplete stream expiry")
    func duplicateChunksDoNotExtendExpiry() {
        // Given
        var now = ContinuousClock().now
        let id = UUID()
        let receiver = SharePlayPackageReceiver(
            expirationInterval: .seconds(30),
            now: { now }
        )
        let first = Self.incompletePackage(id: id, count: 1, data: "first")
        _ = receiver.received(package: first, from: Self.packageSourceParticipantId)

        // When
        now = now.advanced(by: .seconds(29))
        _ = receiver.received(package: first, from: Self.packageSourceParticipantId)
        now = now.advanced(by: .seconds(1))

        // Then
        #expect(receiver.pruneExpired() == 1)
        #expect(receiver.receivedPackages.isEmpty)
    }

    @Test("receiver expires abandoned streams without another incoming package")
    func receiverSchedulesAbandonedStreamExpiry() async {
        // Given
        var now = ContinuousClock().now
        let sleepGate = ReceiverExpirationSleepGate()
        let receiver = SharePlayPackageReceiver(
            expirationInterval: .seconds(30),
            now: { now },
            sleep: { duration in
                await sleepGate.sleep(for: duration)
            }
        )
        _ = receiver.received(
            package: Self.incompletePackage(id: UUID(), count: 1),
            from: Self.packageSourceParticipantId
        )
        await sleepGate.waitUntilSleeping()

        // When
        now = now.advanced(by: .seconds(30))
        await sleepGate.resume()
        await Task.yield()
        await Task.yield()

        // Then
        #expect(receiver.receivedPackages.isEmpty)
        #expect(receiver.cumulativeIncompleteByteCount == 0)
    }

    @Test("completed package reassembly and JSON decoding run through the off-main helper")
    func completedPackageDecodesGameMessage() async throws {
        // Given
        let model = Self.message(type: .update, module: .dice, data: Data("dice".utf8))
        let encoded = try #require(model.encodeData())
        let splitIndex = encoded.count / 2
        let streamId = UUID()
        let receiver = SharePlayPackageReceiver()
        _ = receiver.received(package: PackageMessage(
            uuid: streamId,
            count: 2,
            total: 2,
            data: encoded[splitIndex..<encoded.count]
        ), from: Self.packageSourceParticipantId)

        // When
        let completed = try #require(receiver.received(package: PackageMessage(
            uuid: streamId,
            count: 1,
            total: 2,
            data: encoded[0..<splitIndex]
        ), from: Self.packageSourceParticipantId))
        let decoded = await RPGSharePlayController.decodedMessage(from: completed)

        // Then
        #expect(decoded?.byteCount == encoded.count)
        #expect(decoded?.model.counter == model.counter)
        #expect(decoded?.model.type == model.type)
        #expect(decoded?.model.data.id == model.data.id)
        #expect(decoded?.model.data.data == model.data.data)
        #expect(completed.sourceParticipantId == Self.packageSourceParticipantId)
    }

    @Test("receiver expires an incomplete stream without sleeping")
    func receiverExpiresIncompleteStream() {
        // Given
        var now = ContinuousClock().now
        let id = UUID()
        let receiver = SharePlayPackageReceiver(
            expirationInterval: .seconds(30),
            now: { now }
        )
        _ = receiver.received(package: PackageMessage(
            uuid: id,
            count: 1,
            total: 2,
            data: Data("first".utf8)
        ), from: Self.packageSourceParticipantId)

        // When
        now = now.advanced(by: .seconds(30))
        let removedCount = receiver.pruneExpired()

        // Then
        #expect(removedCount == 1)
        #expect(receiver.receivedPackages.isEmpty)
    }

    @Test("receiver caps incomplete streams by evicting the least recently progressing")
    func receiverCapsIncompleteStreams() {
        // Given
        let firstId = UUID()
        let secondId = UUID()
        let thirdId = UUID()
        let receiver = SharePlayPackageReceiver(maxIncompleteStreams: 2)
        _ = receiver.received(
            package: Self.incompletePackage(id: firstId, count: 1),
            from: Self.packageSourceParticipantId
        )
        _ = receiver.received(
            package: Self.incompletePackage(id: secondId, count: 1),
            from: Self.packageSourceParticipantId
        )
        _ = receiver.received(
            package: Self.incompletePackage(id: firstId, count: 1),
            from: Self.packageSourceParticipantId
        )

        // When
        _ = receiver.received(
            package: Self.incompletePackage(id: thirdId, count: 1),
            from: Self.packageSourceParticipantId
        )

        // Then
        #expect(Set(receiver.receivedPackages.keys.map(\.packageId)) == [secondId, thirdId])
    }

    @Test("session configuration waits for join to be requested and joined")
    func sessionConfigurationWaitsForJoinRequestAndJoinedState() {
        let sessionId = UUID()
        var lifecycle = SharePlaySessionLifecycle()
        lifecycle.prepare(sessionId: sessionId)

        let configuredBeforeJoin = lifecycle.didEnterJoinedState(sessionId: sessionId)
        #expect(!configuredBeforeJoin)

        lifecycle.didRequestJoin(sessionId: sessionId)

        let configuredAfterJoin = lifecycle.didEnterJoinedState(sessionId: sessionId)
        let configuredTwice = lifecycle.didEnterJoinedState(sessionId: sessionId)
        #expect(configuredAfterJoin)
        #expect(!configuredTwice)
    }

    @Test("SharePlay selection remains visible while waiting and reconnecting")
    func sharePlaySelectionDrivesConnectionPresentation() {
        // Given
        let controller = RPGSharePlayController()
        #expect(controller.connectionState == .inactive)

        // When - the game starts before the system delivers a GroupSession.
        controller.joinGame()

        // Then - the UI can show SharePlay waiting instead of a Wi-Fi status.
        #expect(controller.connectionState == .waiting)

        // When - transport resources reset while sessions() keeps listening
        // for an automatic rejoin.
        controller.reset()

        // Then
        #expect(controller.connectionState == .waiting)

        // When
        controller.stopJoin()

        // Then
        #expect(controller.connectionState == .inactive)
    }

    @Test("events from an old SharePlay session cannot configure a replacement session")
    func oldSessionEventsCannotConfigureReplacementSession() {
        let oldSessionId = UUID()
        let currentSessionId = UUID()
        var lifecycle = SharePlaySessionLifecycle()
        lifecycle.prepare(sessionId: oldSessionId)
        lifecycle.didRequestJoin(sessionId: oldSessionId)
        lifecycle.prepare(sessionId: currentSessionId)

        #expect(!lifecycle.isCurrent(sessionId: oldSessionId))
        #expect(lifecycle.isCurrent(sessionId: currentSessionId))
        let oldSessionConfigured = lifecycle.didEnterJoinedState(sessionId: oldSessionId)
        #expect(!oldSessionConfigured)

        lifecycle.didRequestJoin(sessionId: currentSessionId)

        let currentSessionConfigured = lifecycle.didEnterJoinedState(sessionId: currentSessionId)
        #expect(currentSessionConfigured)
    }

    @Test("an async send result commits only to its session generation")
    func asyncSendResultRequiresCurrentSessionGeneration() {
        // Given
        let oldSessionId = UUID()
        let replacementSessionId = UUID()
        var lifecycle = SharePlaySessionLifecycle()
        lifecycle.prepare(sessionId: oldSessionId)
        let token = SharePlaySessionOperationToken(
            sessionId: oldSessionId,
            generation: 8
        )

        // Then - the result is initially current, but cancellation or a reset
        // generation invalidates it even before a replacement is prepared.
        #expect(token.canCommit(
            lifecycle: lifecycle,
            currentGeneration: 8,
            taskIsCancelled: false
        ))
        #expect(!token.canCommit(
            lifecycle: lifecycle,
            currentGeneration: 8,
            taskIsCancelled: true
        ))
        #expect(!token.canCommit(
            lifecycle: lifecycle,
            currentGeneration: 9,
            taskIsCancelled: false
        ))

        // When
        lifecycle.prepare(sessionId: replacementSessionId)

        // Then
        #expect(!token.canCommit(
            lifecycle: lifecycle,
            currentGeneration: 8,
            taskIsCancelled: false
        ))
    }

    @Test("journal attachment load gives up when the load never returns")
    func journalAttachmentLoadHonoursDeadline() async {
        await #expect(throws: SharePlayAttachmentLoadAbort.deadlineExceeded) {
            try await SharePlayAttachmentLoadRetry.load(
                deadline: .milliseconds(50),
                pollInterval: .milliseconds(10),
                operation: {
                    try await Task.sleep(for: .seconds(60))
                    return Data("late".utf8)
                }
            )
        }
    }

    @Test("journal attachment load stops once the attachment left the journal")
    func journalAttachmentLoadStopsWhenAttachmentRemoved() async {
        await #expect(throws: SharePlayAttachmentLoadAbort.noLongerCurrent) {
            try await SharePlayAttachmentLoadRetry.load(
                deadline: .seconds(30),
                pollInterval: .milliseconds(10),
                isStillWanted: { false },
                operation: {
                    try await Task.sleep(for: .seconds(60))
                    return Data("late".utf8)
                }
            )
        }
    }

    @Test("journal attachment load within its deadline returns the data")
    func journalAttachmentLoadReturnsDataBeforeDeadline() async throws {
        let data = try await SharePlayAttachmentLoadRetry.load(
            deadline: .seconds(30),
            pollInterval: .milliseconds(10),
            operation: { Data("photo".utf8) }
        )
        #expect(data == Data("photo".utf8))
    }

    @Test("journal attachment load retries while its CloudAsset upload finishes")
    func journalAttachmentLoadRetriesTransientUploadFailure() async throws {
        let probe = AttachmentLoadRetryProbe(failuresRemaining: 2)
        let retryDelays: [Duration] = [.milliseconds(1), .milliseconds(2)]

        let data = try await SharePlayAttachmentLoadRetry.load(
            retryDelays: retryDelays,
            sleep: { delay in
                await probe.recordSleep(delay)
            },
            operation: {
                try await probe.load()
            }
        )

        #expect(data == Data("map".utf8))
        #expect(await probe.attemptCount == 3)
        #expect(await probe.recordedDelays == retryDelays)
    }

    @Test("journal attachment load does not retry cancellation")
    func journalAttachmentLoadDoesNotRetryCancellation() async {
        let probe = AttachmentLoadRetryProbe(failuresRemaining: 0, cancels: true)

        await #expect(throws: CancellationError.self) {
            try await SharePlayAttachmentLoadRetry.load(
                retryDelays: [.milliseconds(1)],
                sleep: { delay in
                    await probe.recordSleep(delay)
                },
                operation: {
                    try await probe.load()
                }
            )
        }

        #expect(await probe.attemptCount == 1)
        #expect(await probe.recordedDelays.isEmpty)
    }

    @Test("journal attachment load does not start when already cancelled")
    func journalAttachmentLoadDoesNotStartWhenAlreadyCancelled() async {
        let probe = AttachmentLoadRetryProbe(failuresRemaining: 0)
        let startGate = AttachmentRetryStartGate()
        let task = Task {
            await startGate.wait()
            return try await SharePlayAttachmentLoadRetry.load(
                retryDelays: [.milliseconds(1)],
                sleep: { _ in },
                operation: {
                    try await probe.load()
                }
            )
        }
        task.cancel()
        await startGate.open()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        #expect(await probe.attemptCount == 0)
    }

    @Test("journal attachment load stops when cancelled during retry delay")
    func journalAttachmentLoadStopsWhenCancelledDuringRetryDelay() async {
        let probe = AttachmentLoadRetryProbe(failuresRemaining: 10)
        let sleepGate = AttachmentRetrySleepGate()
        let task = Task {
            try await SharePlayAttachmentLoadRetry.load(
                retryDelays: [.milliseconds(1), .milliseconds(2)],
                sleep: { delay in
                    await sleepGate.sleep(for: delay)
                },
                operation: {
                    try await probe.load()
                }
            )
        }
        await sleepGate.waitUntilSleeping()
        task.cancel()
        await sleepGate.resume()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        #expect(await probe.attemptCount == 1)
    }

    @Test("journal attachment load exhausts its bounded retry policy")
    func journalAttachmentLoadExhaustsBoundedRetryPolicy() async {
        let probe = AttachmentLoadRetryProbe(failuresRemaining: 10)
        let retryDelays: [Duration] = [.milliseconds(1), .milliseconds(2)]

        await #expect(throws: AttachmentLoadProbeError.self) {
            try await SharePlayAttachmentLoadRetry.load(
                retryDelays: retryDelays,
                sleep: { delay in
                    await probe.recordSleep(delay)
                },
                operation: {
                    try await probe.load()
                }
            )
        }

        #expect(await probe.attemptCount == retryDelays.count + 1)
        #expect(await probe.recordedDelays == retryDelays)
    }

    @Test("new journal maps publish while removal of the previous map is suspended")
    func newJournalMapsPublishWhilePreviousRemovalIsSuspended() async {
        let queue = SharePlayJournalPublicationQueue<TestJournalAttachment>()
        let removalGate = JournalRemovalGate()
        let recorder = JournalPublicationRecorder()
        let firstMap = TestJournalAttachment(id: UUID())
        let secondMap = TestJournalAttachment(id: UUID())
        let thirdMap = TestJournalAttachment(id: UUID())

        let firstPublication = queue.enqueue(for: .map) {
            recorder.record(firstMap)
            return firstMap
        } remove: { attachment in
            await removalGate.suspendRemoval(of: attachment.id)
            return true
        }
        await firstPublication.value

        let secondPublication = queue.enqueue(for: .map) {
            recorder.record(secondMap)
            return secondMap
        } remove: { attachment in
            await removalGate.suspendRemoval(of: attachment.id)
            return true
        }
        await secondPublication.value
        await removalGate.waitUntilRemovalStarts(for: firstMap.id)

        // Map one is still being removed. Publishing map three must only wait
        // for map two's add/commit, not for that cleanup operation.
        let thirdPublication = queue.enqueue(for: .map) {
            recorder.record(thirdMap)
            return thirdMap
        } remove: { attachment in
            await removalGate.suspendRemoval(of: attachment.id)
            return true
        }
        await thirdPublication.value

        #expect(recorder.attachmentIds == [firstMap.id, secondMap.id, thirdMap.id])
        #expect(queue.currentAttachment(for: .map)?.id == thirdMap.id)

        await removalGate.releaseAll()
        await Task.yield()
        queue.cancelAll()
    }

    @Test("suspended Journal cleanup applies bounded publication backpressure")
    func suspendedJournalCleanupAppliesBoundedBackpressure() async {
        // Given
        let queue = SharePlayJournalPublicationQueue<TestJournalAttachment>(
            maxOutstandingPublications: 1,
            maxOutstandingBytes: 4,
            maxOutstandingCleanups: 2
        )
        let removalGate = JournalRemovalGate()
        let recorder = JournalPublicationRecorder()
        let attachments = (0..<5).map { _ in TestJournalAttachment(id: UUID()) }
        var admissions: [SharePlayJournalPublicationAdmission] = []

        // When - every replacement cleanup remains suspended. The queue keeps
        // both removals retained and rejects later Journal publications rather
        // than cancelling and permanently abandoning an older removal.
        for attachment in attachments {
            let publication = queue.enqueue(
                for: .map,
                byteCount: 4,
                policy: .latestWins
            ) {
                recorder.record(attachment)
                return attachment
            } remove: { oldAttachment in
                await removalGate.suspendRemoval(of: oldAttachment.id)
                return true
            }
            admissions.append(publication.admission)
            await publication.value
        }
        await Task.yield()

        // Then
        #expect(admissions == [.enqueued, .enqueued, .enqueued, .rejected, .rejected])
        #expect(recorder.attachmentIds == attachments.prefix(3).map(\.id))
        #expect(queue.currentAttachment(for: .map)?.id == attachments[2].id)
        #expect(queue.outstandingPublicationCount == 0)
        #expect(queue.outstandingPublicationByteCount == 0)
        #expect(queue.outstandingCleanupCount <= 2)

        // A Messenger fallback can still retire the stale current attachment
        // through one bounded emergency slot for this module. Journal stays
        // degraded until that retirement finishes.
        let emergencyRetired = queue.retireCurrentAttachment(for: .map) { attachment in
            await removalGate.suspendRemoval(of: attachment.id)
            return true
        }
        await removalGate.waitUntilRemovalStarts(for: attachments[2].id)
        let journalWhileRetiring = queue.enqueue(for: .map) {
            TestJournalAttachment(id: UUID())
        } remove: { _ in true }
        #expect(emergencyRetired)
        #expect(queue.currentAttachment(for: .map) == nil)
        #expect(queue.outstandingCleanupCount == 3)
        #expect(journalWhileRetiring.admission == .rejected)

        await removalGate.releaseAll()
        await Task.yield()
        queue.cancelAll()
    }

    @Test("Messenger fallback retires the stale current Journal attachment")
    func messengerFallbackRetiresCurrentJournalAttachment() async {
        // Given
        let queue = SharePlayJournalPublicationQueue<TestJournalAttachment>(
            maxOutstandingCleanups: 1
        )
        let removalGate = JournalRemovalGate()
        let current = TestJournalAttachment(id: UUID())
        let publication = queue.enqueue(for: .photo) {
            current
        } remove: { _ in true }
        await publication.value

        // When
        let retired = queue.retireCurrentAttachment(for: .photo) { attachment in
            await removalGate.suspendRemoval(of: attachment.id)
            return true
        }
        await removalGate.waitUntilRemovalStarts(for: current.id)

        // Then - the stale attachment is no longer advertised as current even
        // while the system removal is still suspended, and cleanup stays owned.
        #expect(retired)
        #expect(queue.currentAttachment(for: .photo) == nil)
        #expect(queue.outstandingCleanupCount == 1)
        let replacementAdmission = queue.enqueue(for: .photo) {
            TestJournalAttachment(id: UUID())
        } remove: { _ in true }.admission
        #expect(replacementAdmission == .enqueued)

        await removalGate.releaseAll()
        await Task.yield()
        queue.cancelAll()
    }

    @Test("a newer Messenger fallback supersedes an active Journal presentation")
    func messengerFallbackSupersedesActiveJournalPresentation() async {
        // Given - A is current and B is suspended inside Journal.add. With one
        // publication slot, C cannot enter Journal and must use Messenger.
        let queue = SharePlayJournalPublicationQueue<TestJournalAttachment>(
            maxOutstandingPublications: 1,
            maxOutstandingBytes: 4,
            maxOutstandingCleanups: 1
        )
        let publicationGate = JournalPublicationGate()
        let removalGate = JournalRemovalGate()
        let commitRecorder = JournalPublicationRecorder()
        let current = TestJournalAttachment(id: UUID())
        let active = TestJournalAttachment(id: UUID())
        let rejected = TestJournalAttachment(id: UUID())
        let first = queue.enqueue(
            for: .photo,
            byteCount: 4,
            policy: .latestWins
        ) {
            current
        } commit: { attachment in
            commitRecorder.record(attachment)
        } remove: { attachment in
            await removalGate.suspendRemoval(of: attachment.id)
            return true
        }
        await first.value
        let second = queue.enqueue(
            for: .photo,
            byteCount: 4,
            policy: .latestWins
        ) {
            await publicationGate.suspendFirstPublication()
            return active
        } commit: { attachment in
            commitRecorder.record(attachment)
        } remove: { attachment in
            await removalGate.suspendRemoval(of: attachment.id)
            return true
        }
        await publicationGate.waitUntilFirstPublicationStarts()

        // When - merely attempting C advances the presentation generation. The
        // controller's fallback retirement removes A while B is still active.
        let third = queue.enqueue(
            for: .photo,
            byteCount: 4,
            policy: .latestWins
        ) {
            rejected
        } commit: { attachment in
            commitRecorder.record(attachment)
        } remove: { _ in true }
        queue.supersedePresentation(for: .photo)
        let retired = queue.retireCurrentAttachment(for: .photo) { attachment in
            await removalGate.suspendRemoval(of: attachment.id)
            return true
        }
        await removalGate.waitUntilRemovalStarts(for: current.id)
        await publicationGate.resumeFirstPublication()
        await second.value
        await removalGate.waitUntilRemovalStarts(for: active.id)

        // Then - B's late attachment is cleaned through the bounded emergency
        // slot and never becomes current or runs commit/cache/tracker effects.
        #expect(third.admission == .rejected)
        #expect(retired)
        #expect(queue.currentAttachment(for: .photo) == nil)
        #expect(commitRecorder.attachmentIds == [current.id])
        #expect(!commitRecorder.attachmentIds.contains(active.id))
        #expect(!commitRecorder.attachmentIds.contains(rejected.id))
        #expect(queue.outstandingCleanupCount == 2)

        await removalGate.releaseAll()
        await Task.yield()
        queue.cancelAll()
    }

    @Test("pending Journal presentations coalesce to the newest item")
    func pendingJournalPresentationsCoalesceToNewest() async {
        // Given
        let queue = SharePlayJournalPublicationQueue<TestJournalAttachment>(
            maxOutstandingPublications: 2,
            maxOutstandingBytes: 8
        )
        let publicationGate = JournalPublicationGate()
        let recorder = JournalPublicationRecorder()
        let first = TestJournalAttachment(id: UUID())
        let superseded = TestJournalAttachment(id: UUID())
        let newest = TestJournalAttachment(id: UUID())
        let firstPublication = queue.enqueue(
            for: .photo,
            byteCount: 4,
            policy: .latestWins
        ) {
            await publicationGate.suspendFirstPublication()
            guard !Task.isCancelled else { return nil }
            recorder.record(first)
            return first
        } remove: { _ in true }
        await publicationGate.waitUntilFirstPublicationStarts()
        let supersededPublication = queue.enqueue(
            for: .photo,
            byteCount: 4,
            policy: .latestWins
        ) {
            recorder.record(superseded)
            return superseded
        } remove: { _ in true }

        // When
        let newestPublication = queue.enqueue(
            for: .photo,
            byteCount: 4,
            policy: .latestWins
        ) {
            recorder.record(newest)
            return newest
        } remove: { _ in true }
        await supersededPublication.value

        // Then - the active publication finishes, but only the newest pending
        // presentation retains bytes and reaches the Journal.
        #expect(firstPublication.admission == .enqueued)
        #expect(supersededPublication.admission == .enqueued)
        #expect(newestPublication.admission == .replacedPending)
        #expect(queue.outstandingPublicationCount == 2)
        #expect(queue.outstandingPublicationByteCount == 8)

        await publicationGate.resumeFirstPublication()
        await firstPublication.value
        await newestPublication.value
        #expect(recorder.attachmentIds == [first.id, newest.id])
        #expect(queue.currentAttachment(for: .photo)?.id == newest.id)
        #expect(queue.outstandingPublicationCount == 0)
        #expect(queue.outstandingPublicationByteCount == 0)
        queue.cancelAll()
    }

    @Test("FIFO Journal repairs reject overload without replacing accepted work")
    func fifoJournalRepairsAreBoundedWithoutCoalescing() async {
        // Given
        let queue = SharePlayJournalPublicationQueue<TestJournalAttachment>(
            maxOutstandingPublications: 2,
            maxOutstandingBytes: 8
        )
        let publicationGate = JournalPublicationGate()
        let recorder = JournalPublicationRecorder()
        let first = TestJournalAttachment(id: UUID())
        let second = TestJournalAttachment(id: UUID())
        let rejected = TestJournalAttachment(id: UUID())
        let firstPublication = queue.enqueue(
            for: .audio,
            byteCount: 4,
            policy: .fifo
        ) {
            await publicationGate.suspendFirstPublication()
            guard !Task.isCancelled else { return nil }
            recorder.record(first)
            return first
        } remove: { _ in true }
        await publicationGate.waitUntilFirstPublicationStarts()
        let secondPublication = queue.enqueue(
            for: .audio,
            byteCount: 4,
            policy: .fifo
        ) {
            recorder.record(second)
            return second
        } remove: { _ in true }

        // When
        let rejectedPublication = queue.enqueue(
            for: .audio,
            byteCount: 1,
            policy: .fifo
        ) {
            recorder.record(rejected)
            return rejected
        } remove: { _ in true }
        await rejectedPublication.value

        // Then
        #expect(firstPublication.admission == .enqueued)
        #expect(secondPublication.admission == .enqueued)
        #expect(rejectedPublication.admission == .rejected)
        #expect(queue.outstandingPublicationCount == 2)
        #expect(queue.outstandingPublicationByteCount == 8)

        await publicationGate.resumeFirstPublication()
        await firstPublication.value
        await secondPublication.value
        #expect(recorder.attachmentIds == [first.id, second.id])
        #expect(!recorder.attachmentIds.contains(rejected.id))
        #expect(queue.outstandingPublicationCount == 0)
        #expect(queue.outstandingPublicationByteCount == 0)
        queue.cancelAll()
    }

    @Test("cancelling Journal publications releases waiters and accounting")
    func cancellingJournalPublicationsReleasesAccounting() async {
        // Given
        let queue = SharePlayJournalPublicationQueue<TestJournalAttachment>(
            maxOutstandingPublications: 2,
            maxOutstandingBytes: 8
        )
        let publicationGate = JournalPublicationGate()
        let active = queue.enqueue(
            for: .space,
            byteCount: 4,
            policy: .fifo
        ) {
            await publicationGate.suspendFirstPublication()
            return Task.isCancelled ? nil : TestJournalAttachment(id: UUID())
        } remove: { _ in true }
        await publicationGate.waitUntilFirstPublicationStarts()
        let pending = queue.enqueue(
            for: .space,
            byteCount: 4,
            policy: .fifo
        ) {
            TestJournalAttachment(id: UUID())
        } remove: { _ in true }

        // When
        queue.cancelAll()
        await active.value
        await pending.value

        // Then
        #expect(queue.outstandingPublicationCount == 0)
        #expect(queue.outstandingPublicationByteCount == 0)
        #expect(queue.outstandingCleanupCount == 0)
        #expect(queue.currentAttachment(for: .space)?.id == nil)

        // A cancelled worker that unwinds later cannot clobber the next
        // generation's worker or accounting.
        let replacement = TestJournalAttachment(id: UUID())
        let replacementPublication = queue.enqueue(
            for: .space,
            byteCount: 4,
            policy: .fifo
        ) {
            replacement
        } remove: { _ in true }
        await publicationGate.resumeFirstPublication()
        await replacementPublication.value
        #expect(replacementPublication.admission == .enqueued)
        #expect(queue.currentAttachment(for: .space)?.id == replacement.id)
        #expect(queue.outstandingPublicationCount == 0)
        #expect(queue.outstandingPublicationByteCount == 0)
        queue.cancelAll()
    }

    @Test("a noncooperative Journal add returning after reset is removed as obsolete")
    func noncooperativeJournalAddReturningAfterResetIsRemoved() async {
        // Given
        let queue = SharePlayJournalPublicationQueue<TestJournalAttachment>(
            maxOutstandingCleanups: 1
        )
        let publicationGate = JournalAddGate<TestJournalAttachment>()
        let discardRecorder = JournalDiscardRecorder()
        let commitRecorder = JournalPublicationRecorder()
        let lateAttachment = TestJournalAttachment(id: UUID())
        let publication = queue.enqueue(
            for: .photo,
            policy: .latestWins
        ) {
            await publicationGate.value()
        } commit: { attachment in
            commitRecorder.record(attachment)
        } remove: { attachment in
            await discardRecorder.record(attachment.id)
            return true
        }
        await publicationGate.waitUntilStarted()

        // When - the system add ignores task cancellation and produces an old
        // session attachment only after the queue has reset.
        queue.cancelAll()
        await publication.value
        await publicationGate.resume(returning: lateAttachment)
        await discardRecorder.waitFor(id: lateAttachment.id)
        for _ in 0..<20 where queue.outstandingCleanupCount != 0 {
            await Task.yield()
        }

        // Then - it is removed once through bounded obsolete cleanup, and is
        // never committed or advertised as the current presentation.
        #expect(await discardRecorder.recordedCount(for: lateAttachment.id) == 1)
        #expect(commitRecorder.attachmentIds.isEmpty)
        #expect(queue.currentAttachment(for: .photo) == nil)
        #expect(queue.outstandingCleanupCount == 0)
    }

    @Test("a timed-out Journal add is quarantined per module and its late value is discarded")
    func timedOutJournalAddIsQuarantinedAndDiscarded() async {
        // Given
        let limiter = SharePlayJournalAddLimiter<NetworkModules, TestJournalAttachment>()
        let addGate = JournalAddGate<TestJournalAttachment>()
        let timeoutGate = JournalTimeoutGate()
        let discardRecorder = JournalDiscardRecorder()
        let lateAttachment = TestJournalAttachment(id: UUID())
        let first = Task { @MainActor in
            await limiter.run(
                for: .photo,
                timeout: .seconds(30),
                sleep: { _ in await timeoutGate.sleep() }
            ) {
                await addGate.value()
            } discardLateValue: { attachment in
                await discardRecorder.record(attachment.id)
                return true
            }
        }
        await addGate.waitUntilStarted()
        await timeoutGate.waitUntilStarted()

        // When
        await timeoutGate.fire()
        let firstOutcome = await first.value
        let sameModuleOutcome = await limiter.run(
            for: .photo,
            timeout: .seconds(1)
        ) {
            TestJournalAttachment(id: UUID())
        } discardLateValue: { _ in true }
        let otherModuleAttachment = TestJournalAttachment(id: UUID())
        let otherModuleOutcome = await limiter.run(
            for: .pdf,
            timeout: .seconds(1)
        ) {
            otherModuleAttachment
        } discardLateValue: { _ in true }

        // Then - timeout unblocks Photo without spawning another Photo add;
        // unrelated modules continue, and a late Photo result is removed.
        if case .timedOut = firstOutcome {} else {
            Issue.record("Expected the first Journal add to time out")
        }
        if case .unavailable = sameModuleOutcome {} else {
            Issue.record("Expected the quarantined module to bypass Journal")
        }
        if case .succeeded(let attachment) = otherModuleOutcome {
            #expect(attachment.id == otherModuleAttachment.id)
        } else {
            Issue.record("Expected another module to remain available")
        }
        #expect(limiter.activeCount == 1)

        await addGate.resume(returning: lateAttachment)
        await discardRecorder.waitFor(id: lateAttachment.id)
        for _ in 0..<10 where limiter.activeCount != 0 {
            await Task.yield()
        }
        #expect(limiter.activeCount == 0)
    }

    @Test("an obsolete session add does not quarantine the module in its replacement session")
    func obsoleteSessionJournalAddDoesNotQuarantineReplacementSession() async {
        // Given
        let limiter = SharePlayJournalAddLimiter<NetworkModules, TestJournalAttachment>()
        let oldSessionId = UUID()
        let newSessionId = UUID()
        let addGate = JournalAddGate<TestJournalAttachment>()
        let discardRecorder = JournalDiscardRecorder()
        let lateAttachment = TestJournalAttachment(id: UUID())
        let oldAttempt = Task { @MainActor in
            await limiter.run(
                for: .photo,
                scope: oldSessionId,
                timeout: .seconds(30)
            ) {
                await addGate.value()
            } discardLateValue: { attachment in
                await discardRecorder.record(attachment.id)
                return false
            }
        }
        await addGate.waitUntilStarted()

        // When - replacing the session cancels the old logical waiter, but its
        // non-cooperative system add remains retained under the global bound.
        limiter.cancelAll()
        let oldOutcome = await oldAttempt.value
        let newAttachment = TestJournalAttachment(id: UUID())
        let newOutcome = await limiter.run(
            for: .photo,
            scope: newSessionId,
            timeout: .seconds(1)
        ) {
            newAttachment
        } discardLateValue: { _ in true }

        // Then - Photo is immediately usable in the new scope. A late result
        // from the old scope gets one bounded best-effort cleanup and releases
        // its retained slot even if that invalidated Journal cannot remove it.
        if case .cancelled = oldOutcome {} else {
            Issue.record("Expected the obsolete session waiter to be cancelled")
        }
        if case .succeeded(let attachment) = newOutcome {
            #expect(attachment.id == newAttachment.id)
        } else {
            Issue.record("Expected the replacement session to use Journal")
        }
        #expect(limiter.activeCount == 1)

        await addGate.resume(returning: lateAttachment)
        await discardRecorder.waitFor(id: lateAttachment.id)
        for _ in 0..<10 where limiter.activeCount != 0 {
            await Task.yield()
        }
        #expect(limiter.activeCount == 0)
    }

    @Test("late Journal cleanup stops after one best-effort removal following reset")
    func lateJournalCleanupRechecksResetDuringRetryDelay() async {
        // Given
        let limiter = SharePlayJournalAddLimiter<NetworkModules, TestJournalAttachment>()
        let addGate = JournalAddGate<TestJournalAttachment>()
        let timeoutGate = JournalTimeoutGate()
        let retryProbe = JournalLateCleanupRetryProbe()
        let lateAttachment = TestJournalAttachment(id: UUID())
        let attempt = Task { @MainActor in
            await limiter.run(
                for: .photo,
                scope: UUID(),
                timeout: .seconds(30),
                sleep: { _ in await timeoutGate.sleep() },
                lateCleanupSleep: { duration in
                    try await retryProbe.sleep(for: duration)
                }
            ) {
                await addGate.value()
            } discardLateValue: { attachment in
                await retryProbe.discard(attachment.id)
            }
        }
        await addGate.waitUntilStarted()
        await timeoutGate.waitUntilStarted()
        await timeoutGate.fire()
        let outcome = await attempt.value
        if case .timedOut = outcome {} else {
            Issue.record("Expected the Journal add to time out")
        }

        // When - the first late removal fails and enters its retry delay. A
        // session reset occurs during that suspension.
        await addGate.resume(returning: lateAttachment)
        await retryProbe.waitUntilSleepCount(1)
        limiter.cancelAll()
        await retryProbe.resumeFirstSleep()
        await retryProbe.waitUntilDiscardCount(2)
        for _ in 0..<20 where limiter.activeCount != 0 {
            await Task.yield()
        }

        // Then - cleanup rechecks obsolescence, makes one post-reset attempt,
        // skips another retry delay, and releases the global limiter slot.
        #expect(await retryProbe.discardCount == 2)
        #expect(await retryProbe.sleepCount == 1)
        #expect(limiter.activeCount == 0)
    }

    @Test("late Journal cleanup rechecks reset while removal is suspended")
    func lateJournalCleanupRechecksResetDuringDiscard() async {
        // Given
        let limiter = SharePlayJournalAddLimiter<NetworkModules, TestJournalAttachment>()
        let addGate = JournalAddGate<TestJournalAttachment>()
        let timeoutGate = JournalTimeoutGate()
        let discardGate = JournalLateCleanupDiscardGate()
        let lateAttachment = TestJournalAttachment(id: UUID())
        let attempt = Task { @MainActor in
            await limiter.run(
                for: .photo,
                scope: UUID(),
                timeout: .seconds(30),
                sleep: { _ in await timeoutGate.sleep() },
                lateCleanupSleep: { duration in
                    try await discardGate.sleep(for: duration)
                }
            ) {
                await addGate.value()
            } discardLateValue: { attachment in
                await discardGate.discard(attachment.id)
            }
        }
        await addGate.waitUntilStarted()
        await timeoutGate.waitUntilStarted()
        await timeoutGate.fire()
        let outcome = await attempt.value
        if case .timedOut = outcome {} else {
            Issue.record("Expected the Journal add to time out")
        }

        // When - reset occurs while the first late removal is suspended, and
        // that pre-reset removal subsequently reports failure.
        await addGate.resume(returning: lateAttachment)
        await discardGate.waitUntilDiscardCount(1)
        limiter.cancelAll()
        await discardGate.resumeFirstDiscard()
        await discardGate.waitUntilDiscardCount(2)
        for _ in 0..<20 where limiter.activeCount != 0 {
            await Task.yield()
        }

        // Then - the limiter detects reset immediately, makes one post-reset
        // best-effort removal, skips backoff, and releases its retained slot.
        #expect(await discardGate.discardCount == 2)
        #expect(await discardGate.sleepCount == 0)
        #expect(limiter.activeCount == 0)
    }

    @Test("deferred delivery coalesces presentations and retains targeted repairs")
    func deferredDeliveryIsBoundedAndPurposeAware() {
        // Given
        let sessionId = UUID()
        var queue = SharePlayDeferredDeliveryQueue(maxCount: 2, maxBytes: 64)
        var oldMap = Self.masterMapPresentation(mapId: UUID(), version: 1)
        oldMap.counter = 10
        var newMap = Self.masterMapPresentation(mapId: UUID(), version: 2)
        newMap.counter = 11
        let targetId = UUID()
        let weatherRepair = Self.masterWeatherPayload(
            type: .reveal,
            weatherId: UUID(),
            version: 3,
            targetId: targetId
        )

        // When
        let acceptedOldMap = queue.enqueue(oldMap, sessionId: sessionId, participantId: nil)
        let acceptedNewMap = queue.enqueue(newMap, sessionId: sessionId, participantId: nil)
        let acceptedRepair = queue.enqueue(weatherRepair, sessionId: sessionId, participantId: UUID())

        // Then
        #expect(acceptedOldMap.isAccepted)
        #expect(acceptedNewMap == .replaced)
        #expect(acceptedRepair.isAccepted)
        #expect(queue.count == 2)
        #expect(queue.first?.model.targetId == targetId)
        queue.removeFirst()
        #expect(queue.first?.model.counter == newMap.counter)
    }

    @Test("an older presentation retry preserves newer deferred intent")
    func olderPresentationRetryDoesNotReplaceNewerDeferredIntent() {
        // Given
        let sessionId = UUID()
        let participantId = UUID()
        var queue = SharePlayDeferredDeliveryQueue(maxCount: 3, maxBytes: 128)
        var newerMap = Self.masterMapPresentation(mapId: UUID(), version: 2)
        newerMap.counter = 22
        var olderMapRetry = Self.masterMapPresentation(mapId: UUID(), version: 1)
        olderMapRetry.counter = 21
        let targetId = UUID()
        let weatherId = UUID()
        var repair = Self.masterWeatherPayload(
            type: .reveal,
            weatherId: weatherId,
            version: 7,
            targetId: targetId
        )
        repair.counter = 31
        var repairRetry = repair
        repairRetry.counter = 32

        // When
        let newerAdmission = queue.enqueue(
            newerMap,
            sessionId: sessionId,
            participantId: participantId
        )
        let oldRetryAdmission = queue.enqueue(
            olderMapRetry,
            sessionId: sessionId,
            participantId: participantId,
            deliveryAttempt: 1
        )
        let repairAdmission = queue.enqueue(
            repair,
            sessionId: sessionId,
            participantId: participantId
        )
        let repairRetryAdmission = queue.enqueue(
            repairRetry,
            sessionId: sessionId,
            participantId: participantId,
            deliveryAttempt: 1
        )

        // Then - stale presentation retry is accepted as already covered by
        // newer intent. Exact targeted repairs still replace and stay ahead of
        // presentations in the promotion order.
        #expect(newerAdmission == .enqueued)
        #expect(oldRetryAdmission == .preservedNewerPresentation)
        #expect(repairAdmission == .enqueued)
        #expect(repairRetryAdmission == .replaced)
        #expect(queue.count == 2)
        #expect(queue.first?.model.counter == repairRetry.counter)
        queue.removeFirst()
        #expect(queue.first?.model.counter == newerMap.counter)
    }

    @Test("deferred delivery enforces raw-byte and count bounds")
    func deferredDeliveryEnforcesBounds() {
        let sessionId = UUID()
        var queue = SharePlayDeferredDeliveryQueue(
            maxCount: 1,
            maxBytes: 64,
            maxEntryBytes: 4
        )
        var repair = Self.masterWeatherPayload(
            type: .reveal,
            weatherId: UUID(),
            version: 1,
            targetId: UUID()
        )
        repair.data = NetworkCodableDataType(
            id: repair.data.id,
            type: .weather,
            version: repair.data.version,
            data: Data(repeating: 1, count: 5)
        )

        let accepted = queue.enqueue(repair, sessionId: sessionId, participantId: nil)
        #expect(accepted == .rejectedTooLarge)
        #expect(queue.count == 0)
        #expect(queue.byteCount == 0)
    }

    @Test("a targeted repair evicts deferred presentations before it is rejected")
    func targetedRepairEvictsDeferredPresentations() {
        // Given
        let sessionId = UUID()
        var queue = SharePlayDeferredDeliveryQueue(
            maxCount: 2,
            maxBytes: 8,
            maxEntryBytes: 8
        )
        var map = Self.masterMapPresentation(
            mapId: UUID(),
            version: 1
        )
        map.data = NetworkCodableDataType(
            id: map.data.id,
            type: .map,
            version: map.data.version,
            data: Data(repeating: 1, count: 4)
        )
        var photo = Self.message(
            type: .reveal,
            module: .photo,
            data: Data(repeating: 2, count: 4)
        )
        photo.sender = GameSenderModel(id: photo.masterId, role: .master, name: "Master", characterId: nil)
        var repair = Self.masterWeatherPayload(
            type: .reveal,
            weatherId: UUID(),
            version: 1,
            targetId: UUID()
        )
        repair.data = NetworkCodableDataType(
            id: repair.data.id,
            type: .weather,
            version: repair.data.version,
            data: Data(repeating: 3, count: 4)
        )
        let mapAdmission = queue.enqueue(map, sessionId: sessionId, participantId: nil)
        let photoAdmission = queue.enqueue(photo, sessionId: sessionId, participantId: nil)
        #expect(mapAdmission == .enqueued)
        #expect(photoAdmission == .enqueued)

        // When
        let admission = queue.enqueue(repair, sessionId: sessionId, participantId: UUID())

        // Then - the oldest coalescible presentation yields its count and byte
        // budget; an already-retained targeted repair is never the eviction victim.
        #expect(admission == .enqueuedAfterEvictingPresentations(1))
        #expect(queue.count == 2)
        #expect(queue.byteCount == 8)
        #expect(queue.first?.model.data.type == .weather)
        #expect(queue.first?.model.targetId == repair.targetId)
        queue.removeFirst()
        #expect(queue.first?.model.data.type == .photo)
    }

    @Test("raw Messenger admission conservatively fits the encoded message limit")
    func rawMessengerAdmissionFitsEncodedLimit() {
        let maximum = SharePlayMessengerPayloadBudget.maximumRawPayloadByteCount
        let slashHeavyModel = Self.message(
            type: .reveal,
            module: .photo,
            data: Data(repeating: 0xFF, count: 4_096)
        )
        let encoded = slashHeavyModel.encodeData()

        #expect(SharePlayMessengerPayloadBudget.accepts(rawPayloadByteCount: maximum))
        #expect(!SharePlayMessengerPayloadBudget.accepts(rawPayloadByteCount: maximum + 1))
        #expect(maximum / 3 * 4 + SharePlayMessengerPayloadBudget.metadataHeadroom <=
            SharePlaySingleQueuePackageSender.maxMessageByteCount)
        #expect(encoded != nil)
        #expect(encoded?.range(of: Data("\\/".utf8)) == nil)
        #expect((encoded?.count ?? .max) <
            4_096 * 4 / 3 + SharePlayMessengerPayloadBudget.metadataHeadroom)
    }

    @Test("a waiting reveal yields to a newer one of its module; stores keep their order")
    func journalPublicationPolicyPreservesStores() {
        // Given
        let photoPresentation = Self.message(
            type: .reveal,
            module: .photo,
            data: Data("photo".utf8)
        )
        var audioRepair = Self.message(
            type: .store,
            module: .audio,
            data: Data("audio".utf8)
        )
        audioRepair.subType = .show

        // When / Then
        #expect(RPGSharePlayController.journalPublicationPolicy(for: photoPresentation) == .latestWins)
        #expect(RPGSharePlayController.journalPublicationPolicy(for: audioRepair) == .fifo)
    }

}

private extension SharePlayPackageTransportTests {
    static let fileBackedModules: [NetworkModules] = [.pdf, .audio, .space, .photo, .map, .weather]
    static let journaledMessageTypes: [RPGMessageType] = [.reveal, .store]
    static let packageSourceParticipantId = UUID()

    static func streamKey(_ packageId: UUID) -> SharePlayPackageStreamKey {
        SharePlayPackageStreamKey(
            sourceParticipantId: packageSourceParticipantId,
            packageId: packageId
        )
    }

    static func incompletePackage(
        id: UUID,
        count: Int,
        data: String? = nil
    ) -> PackageMessage {
        PackageMessage(
            uuid: id,
            count: count,
            total: 3,
            data: Data((data ?? "chunk-\(count)").utf8)
        )
    }

    static func message(type: RPGMessageType, module: NetworkModules, data: Data?) -> GameNetworkModel {
        GameNetworkModel(
            counter: 1,
            proxyCounter: 0,
            type: type,
            subType: type == .store ? .store : .show,
            gameConfig: GameConfigModel(id: UUID(), state: .started, master: .empty),
            data: NetworkCodableDataType(id: UUID(), type: module, version: 1, data: data)
        )
    }

    static func masterPhotoRepair(
        counter: Int,
        photoId: UUID,
        version: Int = 1,
        targetId: UUID
    ) -> GameNetworkModel {
        let masterId = UUID()
        return GameNetworkModel(
            counter: counter,
            proxyCounter: 0,
            type: .store,
            subType: .store,
            masterId: masterId,
            sender: GameSenderModel(
                id: masterId,
                role: .master,
                name: "Master",
                characterId: nil
            ),
            targetId: targetId,
            data: NetworkCodableDataType(
                id: photoId,
                type: .photo,
                version: version,
                data: Data("photo-\(version)".utf8)
            )
        )
    }

    static func masterWeatherPayload(
        type: RPGMessageType,
        weatherId: UUID,
        version: Int,
        targetId: UUID?
    ) -> GameNetworkModel {
        let masterId = UUID()
        return GameNetworkModel(
            counter: 14,
            proxyCounter: 0,
            type: type,
            subType: type == .store ? .store : .show,
            masterId: masterId,
            sender: GameSenderModel(
                id: masterId,
                role: .master,
                name: "Master",
                characterId: nil
            ),
            targetId: targetId,
            data: NetworkCodableDataType(
                id: weatherId,
                type: .weather,
                version: version,
                data: Data("weather-\(version)".utf8)
            )
        )
    }

    static func masterMapPresentation(
        mapId: UUID,
        version: Int,
        assetVersion: Int? = nil
    ) -> GameNetworkModel {
        let masterId = UUID()
        return GameNetworkModel(
            counter: 10,
            proxyCounter: 0,
            type: .reveal,
            subType: .show,
            masterId: masterId,
            sender: GameSenderModel(
                id: masterId,
                role: .master,
                name: "Master",
                characterId: nil
            ),
            targetId: nil,
            data: NetworkCodableDataType(
                id: mapId,
                type: .map,
                version: version,
                data: Data("map".utf8),
                assetVersion: assetVersion
            )
        )
    }

}

enum SharePlayDelegateTestEvent: Hashable, Sendable {
    case configured
    case lostParticipant(UUID)
    case lostConnection
    case joinedParticipant(UUID)
    case messageUpdate
    case fileUpdate
    case fileLoadFailure
    case activeCallbackCompleted
    case postCallbackMutation
    case replacementConfigurationAttempted
    case replacementConfigured
}

enum SharePlaySuspendedHandlerKind: CaseIterable, Sendable {
    case messageUpdate
    case fileUpdate
    case fileLoadFailure

    var event: SharePlayDelegateTestEvent {
        switch self {
        case .messageUpdate:
            .messageUpdate
        case .fileUpdate:
            .fileUpdate
        case .fileLoadFailure:
            .fileLoadFailure
        }
    }
}

@MainActor
private final class SharePlaySessionLifecycleHarness {
    private var lifecycle = SharePlaySessionLifecycle()

    init(sessionId: UUID) {
        lifecycle.prepare(sessionId: sessionId)
    }

    func prepare(sessionId: UUID) {
        lifecycle.prepare(sessionId: sessionId)
    }

    func reset() {
        lifecycle.reset()
    }

    func isCurrent(sessionId: UUID) -> Bool {
        lifecycle.isCurrent(sessionId: sessionId)
    }
}

@MainActor
private final class SuspendedSharePlayDelegateRecorder: SharePlayControllerDelegate {
    private let suspendedEvent: SharePlayDelegateTestEvent
    private(set) var events: [SharePlayDelegateTestEvent] = []
    private var didSuspend = false
    private var suspendedCallback: CheckedContinuation<Void, Never>?
    private var suspensionWaiters: [CheckedContinuation<Void, Never>] = []
    private var eventWaiters: [
        SharePlayDelegateTestEvent: [CheckedContinuation<Void, Never>]
    ] = [:]

    init(suspending suspendedEvent: SharePlayDelegateTestEvent) {
        self.suspendedEvent = suspendedEvent
    }

    func record(_ event: SharePlayDelegateTestEvent) {
        events.append(event)
        eventWaiters.removeValue(forKey: event)?.forEach { $0.resume() }
    }

    func waitUntilSuspended() async {
        guard !didSuspend else { return }
        await withCheckedContinuation { continuation in
            suspensionWaiters.append(continuation)
        }
    }

    func waitUntilRecorded(_ event: SharePlayDelegateTestEvent) async {
        guard !events.contains(event) else { return }
        await withCheckedContinuation { continuation in
            eventWaiters[event, default: []].append(continuation)
        }
    }

    func resumeSuspendedCallback() {
        suspendedCallback?.resume()
        suspendedCallback = nil
    }

    func handleUpdate(_: GameNetworkModel, id _: UUID) async {
        await recordAndSuspendIfNeeded(.messageUpdate)
    }

    func handleFileUpdate(_: GameNetworkModel) async {
        await recordAndSuspendIfNeeded(.fileUpdate)
    }

    func handleFileLoadFailure(_: GameNetworkModel) async {
        await recordAndSuspendIfNeeded(.fileLoadFailure)
    }

    func sharePlayLostPlayer(id: UUID) async {
        await recordAndSuspendIfNeeded(.lostParticipant(id))
    }

    func sharePlayLostConnection() async {
        await recordAndSuspendIfNeeded(.lostConnection)
    }

    func sharePlaySessionConfigured() async {
        await recordAndSuspendIfNeeded(.configured)
    }

    func sharePlayJoinedPlayer(id: UUID) async {
        await recordAndSuspendIfNeeded(.joinedParticipant(id))
    }

    private func recordAndSuspendIfNeeded(_ event: SharePlayDelegateTestEvent) async {
        record(event)
        guard event == suspendedEvent, !didSuspend else { return }
        didSuspend = true
        let waiters = suspensionWaiters
        suspensionWaiters = []
        waiters.forEach { $0.resume() }
        await withCheckedContinuation { continuation in
            suspendedCallback = continuation
        }
    }
}

@MainActor
private final class SharePlayTeardownDelegateRecorder: SharePlayControllerDelegate {
    private(set) var events: [SharePlaySessionTeardownEvent] = []

    func handleUpdate(_: GameNetworkModel, id _: UUID) async {}

    func handleFileUpdate(_: GameNetworkModel) async {}

    func handleFileLoadFailure(_: GameNetworkModel) async {}

    func sharePlayLostPlayer(id: UUID) async {
        events.append(.lostParticipant(id))
        await Task.yield()
    }

    func sharePlayLostConnection() async {
        events.append(.lostConnection)
        await Task.yield()
    }

    func sharePlaySessionConfigured() async {}

    func sharePlayJoinedPlayer(id _: UUID) async {}
}

private actor PackageSendGate {
    private var storage: [PackageMessage] = []
    private var didStartFirstPackage = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var firstPackageContinuation: CheckedContinuation<Void, Never>?

    var packages: [PackageMessage] {
        storage
    }

    func send(_ package: PackageMessage) async {
        storage.append(package)
        guard !didStartFirstPackage else { return }
        didStartFirstPackage = true
        let waiters = startWaiters
        startWaiters = []
        waiters.forEach { $0.resume() }
        await withCheckedContinuation { continuation in
            firstPackageContinuation = continuation
        }
    }

    func waitUntilFirstPackageIsSending() async {
        guard !didStartFirstPackage else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func resumeFirstPackage() {
        firstPackageContinuation?.resume()
        firstPackageContinuation = nil
    }
}

private actor ReceiverExpirationSleepGate {
    private var isSleeping = false
    private var sleepContinuation: CheckedContinuation<Void, Never>?
    private var startWaiters: [CheckedContinuation<Void, Never>] = []

    func sleep(for _: Duration) async {
        isSleeping = true
        let waiters = startWaiters
        startWaiters = []
        waiters.forEach { $0.resume() }
        await withCheckedContinuation { continuation in
            sleepContinuation = continuation
        }
    }

    func waitUntilSleeping() async {
        guard !isSleeping else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func resume() {
        sleepContinuation?.resume()
        sleepContinuation = nil
    }
}

private actor PackageCollector {
    private var storage: [PackageMessage] = []

    var values: [PackageMessage] {
        storage
    }

    func append(_ package: PackageMessage) {
        storage.append(package)
    }
}

private actor TargetedPackageCollector {
    struct Delivery: Sendable {
        let package: PackageMessage
        let participantId: UUID?
    }

    private var storage: [Delivery] = []

    var values: [Delivery] {
        storage
    }

    func append(_ package: PackageMessage, participantId: UUID?) {
        storage.append(Delivery(package: package, participantId: participantId))
    }
}

private actor PackageSendRetryProbe {
    private var failuresRemaining: Int
    private(set) var attemptCount = 0
    private(set) var sentPackageCount = 0

    init(failuresRemaining: Int) {
        self.failuresRemaining = failuresRemaining
    }

    func send(_: PackageMessage) throws {
        attemptCount += 1
        if failuresRemaining > 0 {
            failuresRemaining -= 1
            throw PackageSendProbeError.transient
        }
        sentPackageCount += 1
    }
}

private enum PackageSendProbeError: Error {
    case transient
}

private actor AttachmentLoadRetryProbe {
    private var failuresRemaining: Int
    private let cancels: Bool
    private(set) var attemptCount = 0
    private(set) var recordedDelays: [Duration] = []

    init(failuresRemaining: Int, cancels: Bool = false) {
        self.failuresRemaining = failuresRemaining
        self.cancels = cancels
    }

    func load() throws -> Data {
        attemptCount += 1
        if cancels {
            throw CancellationError()
        }
        if failuresRemaining > 0 {
            failuresRemaining -= 1
            throw AttachmentLoadProbeError.uploadInProgress
        }
        return Data("map".utf8)
    }

    func recordSleep(_ delay: Duration) {
        recordedDelays.append(delay)
    }
}

private actor AttachmentRetryStartGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func open() {
        isOpen = true
        let currentWaiters = waiters
        waiters = []
        currentWaiters.forEach { $0.resume() }
    }
}

private actor AttachmentRetrySleepGate {
    private var isSleeping = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var sleepWaiter: CheckedContinuation<Void, Never>?

    func sleep(for _: Duration) async {
        isSleeping = true
        let currentStartWaiters = startWaiters
        startWaiters = []
        currentStartWaiters.forEach { $0.resume() }
        await withCheckedContinuation { continuation in
            sleepWaiter = continuation
        }
    }

    func waitUntilSleeping() async {
        guard !isSleeping else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func resume() {
        sleepWaiter?.resume()
        sleepWaiter = nil
    }
}

private enum AttachmentLoadProbeError: Error {
    case uploadInProgress
}

private actor JournalAddGate<Value: Sendable> {
    private var valueContinuation: CheckedContinuation<Value, Never>?
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var didStart = false

    func value() async -> Value {
        didStart = true
        let waiters = startWaiters
        startWaiters = []
        waiters.forEach { $0.resume() }
        return await withCheckedContinuation { continuation in
            valueContinuation = continuation
        }
    }

    func waitUntilStarted() async {
        guard !didStart else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func resume(returning value: Value) {
        valueContinuation?.resume(returning: value)
        valueContinuation = nil
    }
}

private actor JournalTimeoutGate {
    private var timeoutContinuation: CheckedContinuation<Void, Never>?
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var didStart = false

    func sleep() async {
        didStart = true
        let waiters = startWaiters
        startWaiters = []
        waiters.forEach { $0.resume() }
        await withCheckedContinuation { continuation in
            timeoutContinuation = continuation
        }
    }

    func waitUntilStarted() async {
        guard !didStart else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func fire() {
        timeoutContinuation?.resume()
        timeoutContinuation = nil
    }
}

private actor JournalDiscardRecorder {
    private var attachmentIds: Set<UUID> = []
    private var attachmentCounts: [UUID: Int] = [:]
    private var waiters: [UUID: [CheckedContinuation<Void, Never>]] = [:]

    func record(_ attachmentId: UUID) {
        attachmentIds.insert(attachmentId)
        attachmentCounts[attachmentId, default: 0] += 1
        waiters.removeValue(forKey: attachmentId)?.forEach { $0.resume() }
    }

    func recordedCount(for attachmentId: UUID) -> Int {
        attachmentCounts[attachmentId, default: 0]
    }

    func waitFor(id attachmentId: UUID) async {
        guard !attachmentIds.contains(attachmentId) else { return }
        await withCheckedContinuation { continuation in
            waiters[attachmentId, default: []].append(continuation)
        }
    }
}

private actor JournalLateCleanupRetryProbe {
    private(set) var discardCount = 0
    private(set) var sleepCount = 0
    private var discardWaiters: [Int: [CheckedContinuation<Void, Never>]] = [:]
    private var sleepWaiters: [Int: [CheckedContinuation<Void, Never>]] = [:]
    private var firstSleepContinuation: CheckedContinuation<Void, Never>?

    func discard(_: UUID) -> Bool {
        discardCount += 1
        discardWaiters.removeValue(forKey: discardCount)?.forEach { $0.resume() }
        return false
    }

    func sleep(for _: Duration) async throws {
        sleepCount += 1
        sleepWaiters.removeValue(forKey: sleepCount)?.forEach { $0.resume() }
        guard sleepCount == 1 else { throw CancellationError() }
        await withCheckedContinuation { continuation in
            firstSleepContinuation = continuation
        }
    }

    func waitUntilDiscardCount(_ expectedCount: Int) async {
        guard discardCount < expectedCount else { return }
        await withCheckedContinuation { continuation in
            discardWaiters[expectedCount, default: []].append(continuation)
        }
    }

    func waitUntilSleepCount(_ expectedCount: Int) async {
        guard sleepCount < expectedCount else { return }
        await withCheckedContinuation { continuation in
            sleepWaiters[expectedCount, default: []].append(continuation)
        }
    }

    func resumeFirstSleep() {
        firstSleepContinuation?.resume()
        firstSleepContinuation = nil
    }
}

private actor JournalLateCleanupDiscardGate {
    private(set) var discardCount = 0
    private(set) var sleepCount = 0
    private var discardWaiters: [Int: [CheckedContinuation<Void, Never>]] = [:]
    private var firstDiscardContinuation: CheckedContinuation<Void, Never>?

    func discard(_: UUID) async -> Bool {
        discardCount += 1
        discardWaiters.removeValue(forKey: discardCount)?.forEach { $0.resume() }
        if discardCount == 1 {
            await withCheckedContinuation { continuation in
                firstDiscardContinuation = continuation
            }
        }
        return false
    }

    func sleep(for _: Duration) throws {
        sleepCount += 1
        throw CancellationError()
    }

    func waitUntilDiscardCount(_ expectedCount: Int) async {
        guard discardCount < expectedCount else { return }
        await withCheckedContinuation { continuation in
            discardWaiters[expectedCount, default: []].append(continuation)
        }
    }

    func resumeFirstDiscard() {
        firstDiscardContinuation?.resume()
        firstDiscardContinuation = nil
    }
}

private struct TestJournalAttachment: Identifiable, Sendable {
    let id: UUID
}

private struct JournalMetadataFixture {
    let attachmentId: UUID
    let metadata: GameNetworkModel
}

@MainActor
private final class JournalPublicationRecorder {
    private(set) var attachmentIds: [UUID] = []

    func record(_ attachment: TestJournalAttachment) {
        attachmentIds.append(attachment.id)
    }
}

private actor JournalRemovalGate {
    private var startedAttachmentIds: Set<UUID> = []
    private var startWaiters: [UUID: [CheckedContinuation<Void, Never>]] = [:]
    private var removalWaiters: [CheckedContinuation<Void, Never>] = []
    private var isReleased = false

    func suspendRemoval(of attachmentId: UUID) async {
        startedAttachmentIds.insert(attachmentId)
        startWaiters.removeValue(forKey: attachmentId)?.forEach { $0.resume() }
        guard !isReleased else { return }
        await withCheckedContinuation { continuation in
            removalWaiters.append(continuation)
        }
    }

    func waitUntilRemovalStarts(for attachmentId: UUID) async {
        guard !startedAttachmentIds.contains(attachmentId) else { return }
        await withCheckedContinuation { continuation in
            startWaiters[attachmentId, default: []].append(continuation)
        }
    }

    func releaseAll() {
        isReleased = true
        let waiters = removalWaiters
        removalWaiters = []
        waiters.forEach { $0.resume() }
    }
}

private actor JournalPublicationGate {
    private var didStartFirstPublication = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var publicationWaiter: CheckedContinuation<Void, Never>?

    func suspendFirstPublication() async {
        guard !didStartFirstPublication else { return }
        didStartFirstPublication = true
        let currentStartWaiters = startWaiters
        startWaiters = []
        currentStartWaiters.forEach { $0.resume() }
        await withCheckedContinuation { continuation in
            publicationWaiter = continuation
        }
    }

    func waitUntilFirstPublicationStarts() async {
        guard !didStartFirstPublication else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func resumeFirstPublication() {
        publicationWaiter?.resume()
        publicationWaiter = nil
    }
}
#endif
