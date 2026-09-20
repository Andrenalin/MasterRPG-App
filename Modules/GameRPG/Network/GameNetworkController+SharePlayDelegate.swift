// @copyright André Trettin

import CoreRPG
import Foundation
import os.log
import SwiftUI
import GroupActivities

// MARK: - SharePlayControllerDelegate

extension GameNetworkController: SharePlayControllerDelegate {
    func handleUpdate(_ model: GameNetworkModel, id: UUID) async {
        // The messenger already yields messages in order. Await routing so that
        // order is not lost by creating one unstructured task per message.
        await routeSharePlayUpdate(model, id: id)
    }

    func handleFileUpdate(_ model: GameNetworkModel) async {
        // Journal snapshots may briefly contain both an old and replacement
        // attachment. Await routing so their established order is preserved;
        // independent unstructured tasks provide no FIFO guarantee.
        await routeSharePlayFileUpdate(model)
    }

    func handleFileLoadFailure(_ message: GameNetworkModel) async {
        await routeSharePlayFileUpdate(message, callbackKind: .loadFailure)
    }

    func sharePlayLostPlayer(id: UUID) async {
        let lostPinnedMaster = await model.playerDelegate?
            .isPinnedSharePlayMasterParticipant(id: id) == true
        await sharePlayPlayerJournalAdmission.participantLeft(id)
        if lostPinnedMaster {
            await sharePlayDeferredPeerGroupEvents.reset()
        } else {
            await sharePlayDeferredPeerGroupEvents.participantLeft(id)
        }
        await model.masterDelegate?.lostPlayer(for: id)
        await model.playerDelegate?.sharePlayParticipantLeft(id: id)
    }

    func sharePlayLostConnection() async {
        await sharePlayPlayerJournalAdmission.reset()
        await sharePlayDeferredPeerGroupEvents.reset()
        await model.playerDelegate?.lostConnection()
    }

    func sharePlaySessionConfigured() async {
        await sharePlayPlayerJournalAdmission.reset()
        await sharePlayDeferredPeerGroupEvents.reset()
        guard !model.hasLocalPlayer else { return }
        // Keep ready() in the GroupSession state loop. If list reporting
        // suspends, invalidation cannot overtake it and then be clobbered by
        // the obsolete ready operation resuming afterward.
        await model.playerDelegate?.ready()
    }

    func pinnedMasterParticipantId(among participantIds: [UUID]) async -> UUID? {
        guard let playerDelegate = model.playerDelegate else { return nil }
        for id in participantIds where await playerDelegate.isPinnedSharePlayMasterParticipant(id: id) {
            return id
        }
        return nil
    }

    func sharePlayJoinedPlayer(id: UUID) async {
        // `id` is a GroupActivities transport participant, not the player's
        // later in-game sender ID. Preserve that origin so replay is physically
        // addressed through Messenger and can never fall through to Bonjour.
        await model.masterDelegate?.ready(for: .sharePlay(id))
        if model.masterDelegate != nil {
            // The master reference above is first in the targeted Messenger
            // queue, establishing roster/authority before a retained
            // player-authored attachment can be released. Existing Journal
            // bytes then need only their original sender/message/digest
            // admission, not another upload.
            _ = sharePlayStore.reannounceCurrentJournalAdmissions(to: id)
        }
    }

    func routeSharePlayUpdate(_ message: GameNetworkModel, id: UUID) async {
        await routeSharePlayUpdate(
            message,
            id: id,
            allowsUnknownRosterDeferral: true
        )
    }

    private func routeSharePlayUpdate(
        _ message: GameNetworkModel,
        id: UUID,
        allowsUnknownRosterDeferral: Bool
    ) async {
        let origin = GameMessageOrigin.sharePlay(id)
        // GroupSessionMessenger does not echo this device's own sends. On the
        // game-master device, authoritative messages reach the co-located
        // PlayerController through sendPlayer/sendLocalPlayer instead. Therefore
        // any inbound peer envelope claiming to be the master is necessarily a
        // forged logical identity and must not get the first physical binding.
        if message.sender.isMaster, model.hasLocalPlayer {
            Logger.networking.debug("GameNetworkController: Rejected inbound SharePlay master message on the game-master device")
            return
        }
        if message.sender.isMaster,
           let playerDelegate = model.playerDelegate,
           await !playerDelegate.isLocalSharePlayTarget(message.targetId) {
            Logger.networking.debug("GameNetworkController: Ignored master message addressed to another SharePlay player")
            return
        }
        if !message.sender.isMaster {
            guard message.sender.role == .player else {
                Logger.networking.debug("GameNetworkController: Rejected local-only role on SharePlay from \(id)")
                return
            }

            // On the game-master device, MasterController owns the roster and
            // transport binding. Do not mutate the Journal admission state
            // until that authoritative check succeeds, or a forged first
            // packet could poison the actor and deny the real participant.
            if let masterDelegate = model.masterDelegate {
                guard await masterDelegate.accepts(message, origin: origin) else {
                    Logger.networking.debug("GameNetworkController: Rejected unauthenticated SharePlay message from \(id)")
                    return
                }
            } else {
                let isAdmissionRelayedByPinnedMaster: Bool
                if message.isPlayerJournalAdmissionMetadata {
                    isAdmissionRelayedByPinnedMaster = await sharePlayPlayerJournalAdmission.isTrustedMasterRelay(
                        participantID: id
                    )
                } else {
                    isAdmissionRelayedByPinnedMaster = false
                }
                if !isAdmissionRelayedByPinnedMaster {
                    guard let playerDelegate = model.playerDelegate else {
                        Logger.networking.debug("GameNetworkController: Rejected player envelope before SharePlay sender binding")
                        return
                    }
                    let acceptsPeer = await playerDelegate.acceptsSharePlayPeerMessage(
                        message,
                        participantId: id
                    )
                    if !acceptsPeer {
                        let shouldDefer: Bool
                        if allowsUnknownRosterDeferral {
                            shouldDefer = await playerDelegate.shouldDeferSharePlayPeerGroupEvent(
                                message,
                                participantId: id
                            )
                        } else {
                            shouldDefer = false
                        }
                        if shouldDefer {
                            if await sharePlayDeferredPeerGroupEvents.retain(
                                message,
                                participantID: id
                            ) {
                                Logger.networking.debug("GameNetworkController: Deferred player Group event until the next master roster update")
                            } else {
                                Logger.networking.debug("GameNetworkController: Rejected player Group event because the pre-roster deferral is full")
                            }
                            return
                        }
                        Logger.networking.debug("GameNetworkController: Rejected player envelope before SharePlay sender binding")
                        return
                    }
                }
            }
            guard await sharePlayPlayerJournalAdmission.acceptsPlayerMessenger(
                message,
                participantID: id
            ) else {
                Logger.networking.debug("GameNetworkController: Rejected rebound SharePlay sender from \(id)")
                return
            }
        }

        if message.isJournalAdmissionOnly {
            if message.sender.isMaster {
                // A master admission packet is deliberately side-effect free:
                // only a previously authenticated master participant may bind
                // the anonymous attachment. A complete first master envelope
                // may pin session authority, but never enters repair or
                // presentation handlers itself.
                guard let playerDelegate = model.playerDelegate,
                      await playerDelegate.acceptsSharePlayMasterJournalAdmission(
                          message,
                          participantId: id
                      ),
                      await playerDelegate.isPinnedSharePlayMasterParticipant(id: id),
                      await sharePlayPlayerJournalAdmission.trustMasterRelay(
                          participantID: id
                      )
                else {
                    Logger.networking.debug("GameNetworkController: Rejected Journal admission from an unpinned SharePlay master")
                    return
                }
            }

            let admission = await sharePlayPlayerJournalAdmission.admitAnnouncement(
                message,
                participantID: id
            )
            let deferredJournals: [SharePlayDeferredJournalCallback]
            switch admission {
            case .admitted(let callbacks):
                deferredJournals = callbacks
            case .notAdmission, .rejected:
                Logger.networking.debug("GameNetworkController: Rejected conflicting or malformed Journal admission metadata")
                return
            }

            // Journal may surface the attachment before Messenger delivers its
            // participant-attributed control packet. Release only the exact
            // deferred fingerprint, and never route the control packet itself.
            for deferredJournal in deferredJournals {
                await routeSharePlayFileUpdate(
                    deferredJournal.model,
                    callbackKind: deferredJournal.kind
                )
            }
            return
        }

        if message.sender.isMaster {
            await model.playerDelegate?.receivedSharePlay(message, participantId: id)
            let isPinnedMaster = await model.playerDelegate?
                .isPinnedSharePlayMasterParticipant(id: id) == true
            if isPinnedMaster {
                _ = await sharePlayPlayerJournalAdmission.trustMasterRelay(
                    participantID: id
                )
            }
            if isPinnedMaster,
               let playerDelegate = model.playerDelegate,
               await playerDelegate.didAcceptSharePlayMasterState(
                   message,
                   participantId: id
               ) {
                let deferredEvents = await sharePlayDeferredPeerGroupEvents.drain()
                for deferredEvent in deferredEvents {
                    // One roster update is the complete waiting window. Every
                    // event now takes the ordinary authority and physical
                    // sender-binding path and can never be deferred again.
                    await routeSharePlayUpdate(
                        deferredEvent.model,
                        id: deferredEvent.participantID,
                        allowsUnknownRosterDeferral: false
                    )
                }
            }
        } else {
            // Match the LAN-ingress ordering: once the physical SharePlay
            // sender is authenticated, peer-visible player intent must cross
            // the bridge before the master canonicalizes it. Otherwise a
            // mismatched Photo/PDF/Space reveal can make the master broadcast
            // its canonical asset first and then leave LAN peers displaying
            // the stale raw player event that is relayed afterward.
            if model.hasLocalPlayer,
               Self.shouldRelayToLAN(message),
               await relayAdmission.admit(message) {
                await model.masterStore?.sendResponse(data: message)
            }
            await model.masterDelegate?.received(message, origin: origin)
            if !model.hasLocalPlayer, Self.shouldRelayToLAN(message) {
                await model.playerDelegate?.receivedSharePlay(message, participantId: id)
            }
        }
    }

    func routeSharePlayFileUpdate(
        _ message: GameNetworkModel,
        callbackKind: SharePlayJournalCallbackKind = .update
    ) async {
        // Journal snapshots can include locally published attachments, but the
        // master already delivered those to its local player at send time. Do
        // not let either a duplicate snapshot or a peer-forged master envelope
        // enter the local player's authority path.
        if message.sender.isMaster, model.hasLocalPlayer {
            Logger.networking.debug("GameNetworkController: Rejected inbound SharePlay master file message on the game-master device")
            return
        }
        if message.sender.isMaster,
           let playerDelegate = model.playerDelegate,
           await !playerDelegate.isLocalSharePlayTarget(message.targetId) {
            Logger.networking.debug("GameNetworkController: Ignored Journal repair addressed to another SharePlay player")
            return
        }
        switch await sharePlayPlayerJournalAdmission.disposition(
            forJournal: message,
            callbackKind: callbackKind
        ) {
        case .authorized:
            break
        case .deferred:
            Logger.networking.debug("GameNetworkController: Deferred Journal message until its SharePlay announcement")
            return
        case .rejected:
            Logger.networking.debug("GameNetworkController: Rejected uncorrelated SharePlay file message")
            return
        }
        if !message.sender.isMaster,
           let masterDelegate = model.masterDelegate,
           await !masterDelegate.accepts(message, origin: .file) {
            Logger.networking.debug("GameNetworkController: Rejected unauthenticated SharePlay file message")
            return
        }
        sharePlayStore.markJournalAttachmentAuthenticated(message)

        if message.sender.isMaster {
            switch callbackKind {
            case .update:
                await model.playerDelegate?.receivedSharePlayFile(message)
            case .loadFailure:
                await model.playerDelegate?.sharePlayFileLoadFailed(message)
            }
        } else {
            // Journal delivery uses the same bridge ordering as Messenger.
            // `shouldRelayToLAN` still excludes Character synchronization,
            // reports, acknowledgements, and repair requests.
            if model.hasLocalPlayer,
               Self.shouldRelayToLAN(message),
               await relayAdmission.admit(message) {
                await model.masterStore?.sendResponse(data: message)
            }
            await model.masterDelegate?.receivedFile(message)
            if !model.hasLocalPlayer, Self.shouldRelayToLAN(message) {
                await model.playerDelegate?.receivedSharePlayFile(message)
            }
        }
    }
}
