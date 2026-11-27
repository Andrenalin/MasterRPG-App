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

// The session configuration and its observation tasks, split out of RPGSharePlayController+SessionLifecycle.swift. See CODE_AUDIT_29 §9.9.

extension RPGSharePlayController {
    /// Clears the state of an earlier session before `groupSession` is configured. Returns
    /// `false` when there is nothing to configure: the task was cancelled (the session is left)
    /// or this very session is configured already.
    func prepareForConfiguration(_ groupSession: GroupSession<RPGActivity>) async -> Bool {
        // An invalidated-state worker resets synchronously, then performs its
        // delegate cleanup asynchronously. Do not let sessions() configure a
        // replacement inside that suspension window.
        await sessionTeardownCoordinator.waitForPendingTeardown()
        guard !Task.isCancelled else {
            leaveUnconfiguredSession(groupSession)
            return false
        }

        if self.groupSession?.id == groupSession.id,
           messenger != nil,
           journal != nil,
           packageSender != nil {
            Logger.sharePlay.debug("Configure Session ignored duplicate \(groupSession.id, privacy: .public)")
            return false
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
            guard !Task.isCancelled else {
                leaveUnconfiguredSession(groupSession)
                return false
            }
        } else {
            // `reset()` above already resets the tracker for the
            // replace-an-existing-session path (and `drainSessionTeardownEvents()`
            // resets `participantTracker` a second time before that even
            // runs) — redundant but harmless there. This `else` is reached
            // only on the first-ever configure, where neither of those ran,
            // so it's the sole place it actually needs resetting. See
            // CODE_AUDIT_Reconnect §9.1.
            participantTracker.reset()
        }

        return true
    }

    /// Follows the session's state: joined (configured, replay), invalidated (teardown).
    func makeStateTask(groupSession: GroupSession<RPGActivity>) -> Task<Void, Never> {
        Task { @MainActor [weak self] in
            for await state in groupSession.$state.values {
                guard let self else { return }
                guard !Task.isCancelled,
                      self.sessionLoopIsCurrent(sessionId: groupSession.id)
                else { return }
                let stateDescription = self.printState()
                Logger.sharePlay.debug("Session state: \(stateDescription, privacy: .public)")
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
    }

    /// Follows the participant roster by transport identity. An initial snapshot may arrive before
    /// `.joined`; the tracker retains it and the state task replays those participants once.
    func makeParticipantTask(groupSession: GroupSession<RPGActivity>) -> Task<Void, Never> {
        Task { @MainActor [weak self] in
            for await _ in groupSession.$activeParticipants.values {
                guard let self,
                      !Task.isCancelled,
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
    }

    /// Reassembles the chunked Messenger packages and hands each complete message to the delegate.
    func makeMessageTask(groupSession: GroupSession<RPGActivity>, messenger: GroupSessionMessenger) -> Task<Void, Never> {
        Task { @MainActor [weak self] in
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
                   self.admitsInboundPackage(completedPackage, from: context.source.id) {
                    guard let decodedMessage = await Self.decodedMessage(from: completedPackage) else {
                        // A complete message that does not decode: version skew or corruption.
                        // See CODE_AUDIT_Game_Shareplay §5.19.
                        if !Task.isCancelled {
                            Logger.sharePlay.warning("Chunked ✕: stream \(completedPackage.id, privacy: .public) from \(completedPackage.sourceParticipantId, privacy: .private) (\(completedPackage.byteCount, privacy: .public) bytes) could not be decoded")
                        }
                        continue
                    }
                    let size = Self.formattedByteCount(decodedMessage.byteCount)
                    Logger.sharePlay.debug("Chunked ✓: received \(message.total, privacy: .public) packages, assembled size \(size, privacy: .public) from \(context.source.id, privacy: .public)")
                    guard !Task.isCancelled,
                          self.sessionLifecycle.isCurrent(sessionId: groupSession.id)
                    else { return }
                    let gameModel = decodedMessage.model
                    // A file that came in chunks shows how long they took, as a Journal load does.
                    // A single chunk measured nothing.
                    if completedPackage.transferDuration > .zero, let bytes = gameModel.data.data?.count, bytes > 0 {
                        self.delegate?.sharePlayTransferChanged(
                            ItemTransferStatus(state: .done, duration: completedPackage.transferDuration, byteCount: bytes),
                            for: gameModel
                        )
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
    }

    /// Hands every Journal snapshot to the attachment handling.
    func makeJournalTask(groupSession: GroupSession<RPGActivity>, journal: GroupSessionJournal) -> Task<Void, Never> {
        Task { @MainActor [weak self] in
            for await attachment in journal.attachments {
                guard let self else { return }
                guard !Task.isCancelled,
                      self.sessionLifecycle.isCurrent(sessionId: groupSession.id)
                else { return }
                self.receiveJournalSnapshot(attachment, sessionId: groupSession.id)
            }
        }
    }

    /// Queues the `join()` of `groupSession` and records that it was requested.
    func requestJoin(_ groupSession: GroupSession<RPGActivity>) {
        // Calling join() establishes the ordering guarantee documented by
        // GroupActivities: synchronization requested after this call is queued
        // until the session reaches .joined.
        // The join is requested from the main actor, in a deferred turn (as the TabletopKit
        // coordination does), after this setup has finished, and only for the current session.
        // `join()` itself runs off the main actor: it sets up the call's audio session and
        // blocks while it does, which hangs the UI when the app's own audio session is active
        // (AVAudioSession hang risk). The session's state is still only read on the main
        // actor. Every `join()` and `leave()` of this session goes through one
        // `GroupSessionCommandQueue`, so a `reset()` during a join leaves the session only after
        // the join returned, never at the same time. See CODE_AUDIT_18 §3.8, CODE_AUDIT_24 §3.1.
        let sessionId = groupSession.id
        let commands = GroupSessionCommandQueue(session: groupSession)
        sessionCommands = commands
        let sessionJoinTask = Task { @MainActor [weak self] in
            guard !Task.isCancelled,
                  let self,
                  self.sessionLifecycle.isCurrent(sessionId: sessionId)
            else { return }
            commands.join()
        }
        // reset() now owns cancellation of a delayed join for this session.
        tasks[UUID()] = sessionJoinTask
        sessionLifecycle.didRequestJoin(sessionId: groupSession.id)
    }
}
