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

    /// Whether this platform may use `GroupActivities`. The tvOS targets carry no
    /// `com.apple.developer.group-session` entitlement (and the activity is not offered on
    /// Apple TV), so there the sessions are never started or observed. See CODE_AUDIT_26 §4.15.
    static var supportsGroupSessions: Bool {
#if os(tvOS)
        false
#else
        true
#endif
    }

    func startSharing(with name: String?, image: AKImage?) {
        guard Self.supportsGroupSessions else {
            Logger.sharePlay.debug("SharePlay is not available on this platform")
            return
        }
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
        guard Self.supportsGroupSessions else {
            Logger.sharePlay.debug("SharePlay sessions are not observed on this platform")
            return
        }
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
                Logger.sharePlay.debug("Session \(session.description, privacy: .private) state: \(self.printState(), privacy: .public)")

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
        pendingActivation = nil
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

    /// Leaves a session `sessions()` yielded that this controller will no longer join. Dropping
    /// it unjoined and un-left keeps it pending in the system, and the next `sessions()`
    /// iteration may not offer the activity again (CODE_AUDIT_Game_Shareplay §3.7). The
    /// session in use is never left here: its `leave()` goes through the command queue.
    func leaveUnconfiguredSession(_ session: GroupSession<RPGActivity>) {
        guard self.groupSession?.id != session.id else { return }
        Logger.sharePlay.debug("Leaving yielded session that was cancelled before configuration \(session.id, privacy: .public)")
        session.leave()
    }

    func configureGroupSession(_ groupSession: GroupSession<RPGActivity>) async {
        Logger.sharePlay.debug("Configure Session \(groupSession.description, privacy: .private) state: \(self.printState(), privacy: .public)")

        guard await prepareForConfiguration(groupSession) else { return }

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
        // One task per stream. Each re-binds `self` per element, so none keeps the controller
        // alive for the session's lifetime, and `reset()` cancels all of them.
        tasks[UUID()] = makeStateTask(groupSession: groupSession)
        tasks[UUID()] = makeParticipantTask(groupSession: groupSession)
        tasks[UUID()] = makeMessageTask(groupSession: groupSession, messenger: messenger)
        tasks[UUID()] = makeJournalTask(groupSession: groupSession, journal: journal)

        requestJoin(groupSession)
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

// MARK: - Participant players

extension RPGSharePlayController {
    /// Records which player a participant is. Called for a player message that arrived from
    /// the participant itself and passed the sender checks.
    func bindPlayer(named name: String, playerId: UUID, hasTable: Bool, participantId: UUID) {
        let player = ParticipantPlayer(id: playerId, name: name, hasTable: hasTable)
        guard !name.isEmpty, participantPlayers[participantId] != player else { return }
        participantPlayers[participantId] = player
#if os(visionOS)
        refreshSeatPlayerNames()
        // Whether a nearby participant plays on Vision Pro decides whether the table is turned.
        gameModel?.gameTableModel?.orientTableToLocalSeat()
#endif
    }

    /// Records that the participant behind a message of the game master plays on Vision Pro (or
    /// not). The master is no `participantPlayers` entry, but the table needs to know whether
    /// another Vision Pro shares the session. See `currentSystemSeatPlacement()`.
    func bindMasterPlatform(hasTable: Bool, participantId: UUID) {
        guard participantsWithTable.contains(participantId) != hasTable else { return }
        if hasTable {
            participantsWithTable.insert(participantId)
        } else {
            participantsWithTable.remove(participantId)
        }
#if os(visionOS)
        gameModel?.gameTableModel?.orientTableToLocalSeat()
#endif
    }

    func unbindPlayer(participantId: UUID) {
        guard participantPlayers.removeValue(forKey: participantId) != nil else { return }
#if os(visionOS)
        refreshSeatPlayerNames()
#endif
    }
}
