// @copyright André Trettin

import AudioRPG
import AVFoundation
import CoreRPG
import Combine
import Foundation
import GroupActivities
import os.log
import SwiftUI

#if os(visionOS)
import TabletopKit
#endif

extension RPGSharePlayController {

    // MARK: - Session lifecycle (start / join / stop)

    func startSharing(with name: String?, image: AKImage?) {
        Logger.sharePlay.debug("Start Sharing state: \(self.printState(), privacy: .public)")
        #if os(macOS)
            if let image {
                var imageRect = CGRect(x: 0, y: 0, width: image.size.width, height: image.size.height)
                let imageRef = image.cgImage(forProposedRect: &imageRect, context: nil, hints: nil)
                RPGActivity.titleImage = imageRef
            }
        #else
            RPGActivity.titleImage = image?.cgImage
        #endif
        activationTask?.cancel()
        if let groupSession {
            activationLifecycle.cancelCurrent()
            activationTask = nil
            let activity = RPGActivity(adventureTitle: name ?? "Adventure")
            Logger.sharePlay.debug("GroupSession active state: \(self.printState(), privacy: .public)")
            groupSession.activity = activity
        } else {
            let activityId = UUID()
            let token = activationLifecycle.begin(activityId: activityId)
            let activity = RPGActivity(
                adventureTitle: name ?? "Adventure",
                activationId: activityId
            )
            activationTask = Task { [weak self] in
                do {
                    let activated = try await activity.activate()
                    guard let self else { return }
                    let canCommit = self.activationLifecycle.canCommit(
                        token: token,
                        taskIsCancelled: Task.isCancelled
                    )
                    self.activationLifecycle.didFinish(
                        token: token,
                        activated: activated
                    )
                    self.stopCleanupSessionObserverIfPossible()
                    guard canCommit else { return }
                    self.activationTask = nil
                    Logger.sharePlay.debug("Activate state: \(self.printState(), privacy: .public)")
                } catch {
                    guard let self else { return }
                    let canCommit = self.activationLifecycle.canCommit(
                        token: token,
                        taskIsCancelled: Task.isCancelled
                    )
                    self.activationLifecycle.didFinish(token: token, activated: false)
                    self.stopCleanupSessionObserverIfPossible()
                    guard canCommit else { return }
                    self.activationTask = nil
                    // A cancelled activation (e.g. `stopJoin()`/`reset()` firing mid-activate)
                    // is expected, not a real failure — logging it at `.error` alongside
                    // genuine activation failures buries the latter in device logs. See
                    // CODE_AUDIT.md §3.8.
                    if error is CancellationError {
                        Logger.sharePlay.debug("Activate cancelled state: \(self.printState(), privacy: .public)")
                    } else {
                        Logger.sharePlay.error("Activate error \(error.localizedDescription) state: \(self.printState(), privacy: .public)")
                    }
                }
            }
        }
    }

    func joinGame() {
        Logger.sharePlay.debug("Join state: \(self.printState(), privacy: .public)")
        connectionState = .waiting
        joinTask?.cancel()
        let observerToken = sessionObserverLifecycle.start(acceptsSessions: true)
        startSessionObserver(token: observerToken)
    }

    func startSessionObserver(token observerToken: SharePlaySessionObserverToken) {
        // Store in joinTask (not tasks) so reset() does not cancel it.
        // The for-await loop stays alive across session invalidations and picks
        // up the next session automatically when the player re-joins the call.
        joinTask = Task { @MainActor [weak self] in
            for await session in RPGActivity.sessions() {
                guard let self else { return }
                guard self.sessionObserverLifecycle.isCurrent(
                    token: observerToken,
                    taskIsCancelled: Task.isCancelled
                ) else { return }
                switch self.activationLifecycle.dispositionForSession(
                    activityId: session.activity.activationId,
                    acceptsSessions: self.sessionObserverLifecycle.acceptsSessions
                ) {
                case .configure:
                    break
                case .leave:
                    Logger.sharePlay.debug("Leaving session rejected by activation lifecycle \(session.id, privacy: .public)")
                    session.leave()
                    continue
                case .leaveAndStopCleanup:
                    Logger.sharePlay.debug("Leaving final session from stopped activation \(session.id, privacy: .public)")
                    session.leave()
                    self.sessionObserverLifecycle.stop()
                    self.joinTask = nil
                    return
                }
                guard self.sessionObserverLifecycle.canConfigure(
                    token: observerToken,
                    taskIsCancelled: Task.isCancelled
                ) else {
                    session.leave()
                    return
                }
                Logger.sharePlay.debug("Session \(session.description, privacy: .public) state: \(self.printState(), privacy: .public)")

                await self.configureGroupSession(session)
                guard self.sessionObserverLifecycle.canConfigure(
                    token: observerToken,
                    taskIsCancelled: Task.isCancelled
                ) else { return }
                #if os(visionOS)
                await self.configureSystemCoordinator(for: session)
                #endif
            }
        }
    }

    func stopJoin() {
        Logger.sharePlay.debug("SharePlay: stopJoin")
        connectionState = .inactive
        // Revoke and cancel the normal observer before creating a cleanup-only
        // replacement. An already-admitted configure await cannot commit with
        // its obsolete generation afterward.
        sessionObserverLifecycle.stop()
        joinTask?.cancel()
        joinTask = nil
        cancelActivation()
        if activationLifecycle.hasObsoleteActivities {
            // Keep at most one sessions() subscriber alive in cleanup-only
            // mode so a non-cooperative late activation can be explicitly left.
            let cleanupToken = sessionObserverLifecycle.start(acceptsSessions: false)
            startSessionObserver(token: cleanupToken)
        }
    }

    func cancelActivation() {
        activationTask?.cancel()
        activationTask = nil
        activationLifecycle.cancelCurrent()
    }

    func stopCleanupSessionObserverIfPossible() {
        guard !sessionObserverLifecycle.acceptsSessions,
              !activationLifecycle.hasObsoleteActivities
        else { return }
        sessionObserverLifecycle.stop()
        joinTask?.cancel()
        joinTask = nil
    }

    func configureGroupSession(_ groupSession: GroupSession<RPGActivity>) async {
        Logger.sharePlay.debug("Configure Session \(groupSession.description, privacy: .public) state: \(self.printState(), privacy: .public)")

        // An invalidated-state worker resets synchronously, then performs its
        // delegate cleanup asynchronously. Do not let sessions() configure a
        // replacement inside that suspension window.
        await sessionTeardownCoordinator.waitForPendingTeardown()
        guard !Task.isCancelled else { return }

        if self.groupSession?.id == groupSession.id,
           messenger != nil,
           journal != nil,
           packageSender != nil {
            Logger.sharePlay.debug("Configure Session ignored duplicate \(groupSession.id, privacy: .public)")
            return
        }
        if self.groupSession != nil || messenger != nil || journal != nil || packageSender != nil {
            // RPGActivity.sessions() can yield a replacement before the old
            // state loop reports invalidation. Capture its physical roster,
            // cancel every old worker, then await all loss handling before any
            // replacement loop can announce ready/replay state.
            let previousSessionId = self.groupSession?.id
            let teardownEvents = participantTracker.drainSessionTeardownEvents()
            let teardownDelegate = delegate
            let callbackCoordinator = sessionCallbackCoordinator
            let teardown = sessionTeardownCoordinator.start {
                if let previousSessionId {
                    await callbackCoordinator.waitUntilIdle(sessionId: previousSessionId)
                }
                await Self.reportSessionTeardown(teardownEvents, to: teardownDelegate)
            }
            reset()
            await sessionTeardownCoordinator.waitForCompletion(of: teardown)
            guard !Task.isCancelled else { return }
        } else {
            // `reset()` above already resets both trackers for the
            // replace-an-existing-session path (and `drainSessionTeardownEvents()`
            // resets `participantTracker` a second time before that even
            // runs) — redundant but harmless there. This `else` is reached
            // only on the first-ever configure, where neither of those ran,
            // so it's the sole place these two actually need resetting. See
            // CODE_AUDIT_Reconnect §9.1.
            participantTracker.reset()
            mapRecoveryTracker.reset()
        }

        sessionLifecycle.prepare(sessionId: groupSession.id)
        isActive = false
        self.groupSession = groupSession
        connectionState = .waiting
        let messenger = GroupSessionMessenger(session: groupSession)
        self.messenger = messenger
        // Bind every in-flight package stream to the messenger for this exact
        // session. A later session replacement must not split one UUID stream
        // across two GroupSessionMessenger instances.
        packageSender = SharePlaySingleQueuePackageSender { package, participantId in
            if let participantId {
                guard let participant = groupSession.activeParticipants.first(where: { $0.id == participantId }) else {
                    throw SharePlayPackageDeliveryError.participantNotActive(participantId)
                }
                try await messenger.send(package, to: .only([participant]))
            } else {
                try await messenger.send(package)
            }
        }
        let journal = GroupSessionJournal(session: groupSession)
        self.journal = journal

        #if os(visionOS)
        gameModel?.shareState.isSharePlayActive = false
        #endif
        let stateTask = Task { @MainActor [weak self] in
            for await state in groupSession.$state.values {
                guard let self else { return }
                guard !Task.isCancelled,
                      self.sessionLoopIsCurrent(sessionId: groupSession.id)
                else { return }
                let stateDescription = self.printState()
                Logger.sharePlay.debug("Session state: \(stateDescription, privacy: .public)")
                self.stateText = stateDescription
                switch state {
                case .waiting:
                    self.connectionState = .waiting
                case .joined:
                    self.isActive = true
                    self.connectionState = .joined
                    #if os(visionOS)
                    self.gameModel?.shareState.isSharePlayActive = true
                    #endif
                    if self.sessionLifecycle.didEnterJoinedState(sessionId: groupSession.id) {
                        guard await self.performSessionCallback(sessionId: groupSession.id, operation: {
                            await self.delegate?.sharePlaySessionConfigured()
                        }) else { return }

                        let added = self.participantTracker.sessionDidJoin(
                            activeParticipantIds: Set(groupSession.activeParticipants.map(\.id)),
                            localParticipantId: groupSession.localParticipant.id
                        )
                        for participantId in added.sorted(by: { $0.uuidString < $1.uuidString }) {
                            guard await self.performSessionCallback(sessionId: groupSession.id, operation: {
                                await self.delegate?.sharePlayJoinedPlayer(id: participantId)
                            }) else { return }
                        }
                    }
                case .invalidated:
                    self.connectionState = .disconnected
                    let teardownEvents = self.participantTracker.drainSessionTeardownEvents()
                    let teardownDelegate = self.delegate
                    let callbackCoordinator = self.sessionCallbackCoordinator
                    // Publish the pending operation before reset. A replacement
                    // yielded by sessions() will now observe and await it even
                    // while the first delegate callback is suspended.
                    let teardown = self.sessionTeardownCoordinator.start {
                        await callbackCoordinator.waitUntilIdle(sessionId: groupSession.id)
                        await Self.reportSessionTeardown(teardownEvents, to: teardownDelegate)
                    }
                    self.groupSession = nil
                    self.reset()
                    await self.sessionTeardownCoordinator.waitForCompletion(of: teardown)
                    return
                @unknown default:
                    break
                }
            }
        }
        tasks[UUID()] = stateTask

        // Track transport identities directly. An initial participant snapshot
        // may arrive before `.joined`; the tracker retains it and the state loop
        // replays those participants exactly once after Messenger is ready.
        let participantTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for await _ in groupSession.$activeParticipants.values {
                guard !Task.isCancelled,
                      self.sessionLoopIsCurrent(sessionId: groupSession.id)
                else { return }
                // Treat each stream element as a wake-up signal only, and re-read
                // `groupSession.activeParticipants` live rather than trusting the
                // value the stream delivered. `stateTask`'s `.joined` handler also
                // does a live read (to replay anyone already present the instant
                // we join); the two run as independently-scheduled Tasks with no
                // relative-ordering guarantee, so a backlogged, already-superseded
                // element delivered here could otherwise be diffed against roster
                // state the live read on the other task had already advanced past,
                // producing a spurious "removed" for a still-connected participant.
                // Reading fresh here makes every diff use
                // the same single source of truth: a stale queued wake-up becomes,
                // at worst, a harmless no-op re-check instead of a wrong diff.
                let activeParticipants = groupSession.activeParticipants
                let change = self.participantTracker.participantsChanged(
                    activeParticipantIds: Set(activeParticipants.map(\.id)),
                    localParticipantId: groupSession.localParticipant.id,
                    sessionIsJoined: self.isActive
                )
                Logger.sharePlay.debug("Session Participants active: \(activeParticipants.debugDescription, privacy: .private) added: \(change.added.debugDescription, privacy: .private) removed: \(change.removed.debugDescription, privacy: .private)")
                for participantId in change.removed.sorted(by: { $0.uuidString < $1.uuidString }) {
                    guard await self.performSessionCallback(sessionId: groupSession.id, operation: {
                        await self.delegate?.sharePlayLostPlayer(id: participantId)
                    }) else { return }
                }
                for participantId in change.added.sorted(by: { $0.uuidString < $1.uuidString }) {
                    guard await self.performSessionCallback(sessionId: groupSession.id, operation: {
                        await self.delegate?.sharePlayJoinedPlayer(id: participantId)
                    }) else { return }
                }
            }
        }
        tasks[UUID()] = participantTask

        let messageTask = Task { @MainActor [weak self] in
            for await (message, context) in messenger.messages(of: PackageMessage.self) {
                guard let self else { return }
                guard !Task.isCancelled,
                      self.sessionLifecycle.isCurrent(sessionId: groupSession.id)
                else { return }
                Logger.sharePlay.debug("Received Update Message \(message.uuid, privacy: .public): \(message.count, privacy: .public) - \(message.total, privacy: .public) from \(context.source.id, privacy: .public)")
                if let completedPackage = self.packageReceiver.received(
                    package: message,
                    from: context.source.id
                ),
                   let decodedMessage = await Self.decodedMessage(from: completedPackage) {
                    let size = Self.formattedByteCount(decodedMessage.byteCount)
                    Logger.sharePlay.debug("Chunked ✓: received \(message.total, privacy: .public) packages, assembled size \(size, privacy: .public) from \(context.source.id, privacy: .public)")
                    guard !Task.isCancelled,
                          self.sessionLifecycle.isCurrent(sessionId: groupSession.id)
                    else { return }
                    let gameModel = decodedMessage.model
                    if self.mapRecoveryTracker.shouldSuppressRecoveryRequest(gameModel, from: context.source.id) {
                        Logger.sharePlay.debug("Ignored recent map recovery request for \(gameModel.data.id, privacy: .public) from \(context.source.id, privacy: .public)")
                        continue
                    }
                    guard await self.performSessionCallback(sessionId: groupSession.id, operation: {
                        await self.delegate?.handleUpdate(
                            gameModel,
                            id: completedPackage.sourceParticipantId
                        )
                    }) else { return }
                }
            }
        }
        tasks[UUID()] = messageTask
        let journalTask = Task { @MainActor [weak self] in
            for await attachment in journal.attachments {
                guard let self else { return }
                guard !Task.isCancelled,
                      self.sessionLifecycle.isCurrent(sessionId: groupSession.id)
                else { return }
                await self.handle(attachment, sessionId: groupSession.id)
            }
        }
        tasks[UUID()] = journalTask

        // Calling join() establishes the ordering guarantee documented by
        // GroupActivities: synchronization requested after this call is queued
        // until the session reaches .joined.
        // `GroupSession` is not `Sendable`: joining it from a detached task raced the
        // main-actor tasks above that read its `$state`/`activeParticipants` (hidden by
        // `@preconcurrency`). It is joined on the main actor instead, in a deferred turn
        // (as the TabletopKit coordination does), after this setup has finished; `reset()`
        // runs on the main actor too, so a cancelled join can no longer race the join
        // itself. See CODE_AUDIT_18 §3.8.
        let sessionToJoin = groupSession
        let sessionJoinTask = Task { @MainActor [weak self] in
            guard !Task.isCancelled,
                  let self,
                  self.sessionLifecycle.isCurrent(sessionId: sessionToJoin.id)
            else { return }
            sessionToJoin.join()
        }
        // reset() now owns cancellation of a delayed join for this session.
        tasks[UUID()] = sessionJoinTask
        sessionLifecycle.didRequestJoin(sessionId: groupSession.id)
        playBack?.coordinateWithSession(groupSession)
        #if os(visionOS)
        guard !Task.isCancelled,
              sessionLoopIsCurrent(sessionId: groupSession.id)
        else { return }
        // This call handles the mirror-image ordering of
        // `setup(tabletopGame:gameTableModel:)`'s own call to the same
        // deferred helper: `tabletopGame` is already registered here because
        // the 3D table view opened *before* this SharePlay session did, where
        // that other call site handles a session that was already active
        // before the table view opened. `deferCoordinateAndAssignSeats`'s own
        // `coordinatedTabletopGame` guard keeps the two idempotent against
        // each other regardless of which fires first.
        if let tabletopGame {
            deferCoordinateAndAssignSeats(
                tabletopGame: tabletopGame,
                groupSession: groupSession,
                gameTableModel: gameModel?.gameTableModel
            )
        }
        #endif
    }

    func sessionLoopIsCurrent(sessionId: UUID) -> Bool {
        sessionLifecycle.isCurrent(sessionId: sessionId) &&
            groupSession?.id == sessionId
    }

    func performSessionCallback(
        sessionId: UUID,
        operation: @MainActor () async -> Void
    ) async -> Bool {
        await sessionCallbackCoordinator.perform(
            sessionId: sessionId,
            shouldContinue: { [weak self] in
                self?.sessionLoopIsCurrent(sessionId: sessionId) == true
            },
            operation: operation
        )
    }

    func reportSessionTeardown(
        _ events: [SharePlaySessionTeardownEvent]
    ) async {
        await Self.reportSessionTeardown(events, to: delegate)
    }

    static func reportSessionTeardown(
        _ events: [SharePlaySessionTeardownEvent],
        to delegate: (any SharePlayControllerDelegate)?
    ) async {
        for event in events {
            switch event {
            case .lostParticipant(let participantId):
                await delegate?.sharePlayLostPlayer(id: participantId)
            case .lostConnection:
                await delegate?.sharePlayLostConnection()
            }
        }
    }
}
