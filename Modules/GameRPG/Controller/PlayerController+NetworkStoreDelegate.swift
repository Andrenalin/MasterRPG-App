// @copyright André Trettin

import AdventureRPG
import CoreRPG
import DiceRPG
import Foundation
import os.log
import AudioRPG
import MapRPG
import PhotoRPG
import TableRPG
import CharacterRPG
import WeatherRPG
import PdfRPG
import SpaceRPG
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// MARK: - Send PlayerNetworkStoreDelegate
// Conformance itself is declared alongside the class in PlayerController.swift (Swift requires
// same-file `Sendable` conformance for a class); this extension supplies the requirements.

extension PlayerController {
    func lostConnection() async {
        await resetForLostConnection(preservingSharePlayRebind: false)
    }

    func sharePlayParticipantLeft(id: UUID) async {
        guard gameModel.removeSharePlayMasterParticipant(id: id) else { return }
        await resetForLostConnection(preservingSharePlayRebind: true)
    }

    private func resetForLostConnection(
        preservingSharePlayRebind: Bool
    ) async {
        Logger.networking.debug("PlayerController: Lost Connection - Reset State")
        gameModel.resetForLostConnection(preservingSharePlayRebind: preservingSharePlayRebind)
        root.spaceRoot.spaceGameControllable.resetSpaceTransforms()
        // The master may restart its own battle-round sequence lower than
        // what this device last saw; clear the gate so the next authoritative
        // update isn't rejected forever. See CODE_AUDIT_Game §5.6.
        root.mapRoot.mapGameControllable.battleRoundModel.resetNetworkSequence()
        gameModel.reset(lostMaster: true)
        gameModel.reset(sendPlayer: false)
    }

    func ready() async {
        Logger.networking.debug("PlayerController: Ready")
        gameModel.reset(lostMaster: false)
        await sendAudioList()
        await sendPhotoList()
        await sendPdfList()
        await sendSpaceList()
        await scheduleSendCharacter()
    }

    func receivedFile(_ model: GameNetworkModel) async {
        Logger.networking.debug("PlayerController: FILE Received \(model.counter, privacy: .public): \(model.type.debugDescription, privacy: .public) - \(model.subType.debugDescription, privacy: .public), \(model.data.type.token, privacy: .public) id: \(model.data.id, privacy: .public)")
        let receivesOppositeRole = root.gameModel.gameConfig.isMaster != model.sender.isMaster
        // A player-authored file presentation has already been authenticated by
        // GameNetworkController before it reaches this callback. LAN and
        // SharePlay both fan that group event out to sibling players, so equal
        // player roles are expected here; all other same-role file traffic is
        // still rejected.
        guard receivesOppositeRole || model.isPlayerFilePresentationEvent else { return }
        await receivedProcess(model, origin: .file)
    }

    func received(_ model: GameNetworkModel) async {
        await receivedProcess(model, fromProxy: false)
    }

    func receivedSharePlay(_ model: GameNetworkModel, participantId: UUID) async {
        await receivedProcess(model, origin: .sharePlay(participantId))
    }

    func acceptsSharePlayPeerMessage(
        _ model: GameNetworkModel,
        participantId: UUID
    ) async -> Bool {
        guard model.sender.role == .player,
              model.effectiveAudience == .group,
              GameNetworkModel.acceptsEventTimestamp(model.timestamp),
              await acceptsSessionMessage(
                  model,
                  origin: .sharePlay(participantId)
              )
        else { return false }

        // The master-authored roster is the logical identity authority on a
        // player-only device. Validate it before GameNetworkController commits
        // the physical participant binding, preventing an unknown or wrong-role
        // first packet from poisoning that immutable transport identity.
        return root.gameModel.gameRoster.players.contains {
            $0.id == model.sender.id && $0.type == .player
        }
    }

    func shouldDeferSharePlayPeerGroupEvent(
        _ model: GameNetworkModel,
        participantId: UUID
    ) async -> Bool {
        guard model.isDeferrablePlayerGroupEvent,
              await acceptsSessionMessage(
                  model,
                  origin: .sharePlay(participantId)
              )
        else { return false }

        // An existing non-player roster entry is an authoritative rejection,
        // not an ordering race. Only an entirely absent identity gets one
        // opportunity to wait for the next master roster update.
        return !root.gameModel.gameRoster.players.contains {
            $0.id == model.sender.id
        }
    }

    func didAcceptSharePlayMasterState(
        _ model: GameNetworkModel,
        participantId: UUID
    ) async -> Bool {
        guard model.sender.isMaster,
              model.sender.id == model.masterId,
              model.masterState != nil,
              gameModel.isSharePlayMasterParticipant(id: participantId),
              root.gameModel.gameConfig.master.id == model.masterId
        else { return false }

        return gameModel.hasAppliedMasterState(
            from: model.masterId,
            counter: model.counter
        )
    }

    func acceptsSharePlayMasterJournalAdmission(
        _ model: GameNetworkModel,
        participantId: UUID
    ) async -> Bool {
        guard model.isMasterJournalAdmissionMetadata else { return false }
        return await acceptsSessionMessage(
            model,
            origin: .sharePlay(participantId)
        )
    }

    func isLocalSharePlayTarget(_ targetId: UUID?) async -> Bool {
        guard let targetId else { return true }
        return root.gameModel.gameConfig.id == targetId
    }

    func receivedSharePlayFile(_ model: GameNetworkModel) async {
        let receivesOppositeRole = root.gameModel.gameConfig.isMaster != model.sender.isMaster
        guard receivesOppositeRole || model.isPlayerFilePresentationEvent else { return }
        await receivedProcess(model, origin: .file)
    }

    func isPinnedSharePlayMasterParticipant(id: UUID) async -> Bool {
        gameModel.isSharePlayMasterParticipant(id: id)
    }

    func sharePlayFileLoadFailed(_ model: GameNetworkModel) async {
        guard model.sender.isMaster,
              !root.gameModel.gameConfig.isMaster,
              await acceptsSessionMessage(model, origin: .file)
        else { return }

        if model.type == .reveal {
            // A reveal reference may be fully satisfied by an exact-version
            // local item. The regular handler ACKs that case and requests bytes
            // only when the item or its backing file is unavailable.
            await receivedProcess(model, origin: .file)
            return
        }

        // Metadata-only stores and journaled updates do not consistently ask
        // for missing bytes. Convert the recovery into a store request; the
        // master rebuilds the full module payload and targets its reply here.
        var requestTrigger = model
        requestTrigger.type = .store
        requestTrigger.subType = .store
        let request = await response(for: requestTrigger, isSuccess: true, requestData: true)
        await sendUpstream(model: request)
    }

    func receivedProcess(_ model: GameNetworkModel, fromProxy: Bool = false) async {
        Logger.networking.debug("PlayerController: Received \(model.counter, privacy: .public): \(model.type.debugDescription, privacy: .public) - \(model.subType.debugDescription, privacy: .public), \(model.data.type.token, privacy: .public) id: \(model.data.id, privacy: .public)")

        let origin: GameMessageOrigin = fromProxy ? .proxy(nil) : .direct(nil)
        await receivedProcess(model, origin: origin)
    }

    /// Also called by `relayProxyPresentation` (see `PlayerController+SendMessages.swift`) to
    /// apply an optimistic local presentation, so this stays internal rather than `private`.
    func receivedProcess(_ model: GameNetworkModel, origin: GameMessageOrigin) async {
        // Admission-only metadata is consumed by GameNetworkController after
        // physical SharePlay attribution. It is never a gameplay message.
        guard !model.isJournalAdmissionOnly else { return }
        guard await acceptsSessionMessage(model, origin: origin) else {
            Logger.networking.debug("PlayerController: Message rejected because its sender does not belong to this game session")
            return
        }
        guard await messagePipeline.enqueue(GameMessageEvent(model: model, origin: origin)) else {
            Logger.networking.debug("PlayerController: Duplicate ignored \(model.counter, privacy: .public): \(model.type.debugDescription, privacy: .public) - \(model.subType.debugDescription, privacy: .public), \(model.data.type.token, privacy: .public)")
            return
        }
        await processMessages()
    }

    /// Establishes authority from the first complete master broadcast and then
    /// pins every remote envelope to that session. A locally remapped proxy
    /// presentation is already authenticated by the proxy host controller.
    private func acceptsSessionMessage(
        _ model: GameNetworkModel,
        origin: GameMessageOrigin
    ) async -> Bool {
        let config = root.gameModel.gameConfig
        let acceptsLogicalAuthority: Bool

        if origin == .local {
            acceptsLogicalAuthority = model.masterId == config.master.id
        } else if config.master.type == .master {
            guard model.masterId == config.master.id else { return false }
            if model.sender.isMaster {
                acceptsLogicalAuthority = model.sender.id == config.master.id
            } else {
                acceptsLogicalAuthority = model.sender.id != config.master.id &&
                    model.masterState == nil
            }
        } else {
            // Before discovery, only a self-consistent full master broadcast may
            // establish the authoritative master UUID. Player-to-player traffic
            // cannot race that first message and nominate a different session.
            acceptsLogicalAuthority = model.sender.isMaster &&
                model.sender.id == model.masterId &&
                model.masterState != nil
        }

        guard acceptsLogicalAuthority else { return false }
        guard model.sender.isMaster,
              case let .sharePlay(participantId) = origin
        else { return true }

        // Messenger exposes the physical source participant. Pin that source
        // as well as the logical master UUID so another peer cannot copy the
        // public master identity into a forged envelope. Journal callbacks do
        // not expose a publisher and therefore remain logically authenticated.
        switch gameModel.acceptSharePlayMasterParticipant(
            id: participantId,
            isCompleteMasterBroadcast: model.masterState != nil
        ) {
        case .newlyBound, .alreadyBound:
            return true
        case .rebound:
            // The GroupSession can survive while the master's participant ID
            // changes. Re-announce availability and Character exactly as on a
            // fresh session so the rejoined master rebuilds its reports.
            await ready()
            return true
        case .rejected:
            return false
        }
    }

    private func isRemappedProxyPresentation(_ event: GameMessageEvent) -> Bool {
        let model = event.model
        guard event.origin == .local || event.fromProxy else { return false }
        return model.isPlayerFilePresentationEvent
    }

    private func prepareForProcessing(_ event: GameMessageEvent) async -> Bool {
        let model = event.model

        // Targeted messages are only processed by the addressee. Proxy clients
        // are deliberately invisible upstream and every proxy request is remapped
        // to its host ID, so a target belonging to another host can never live
        // behind this device.
        if let targetId = model.targetId, targetId != root.gameModel.gameConfig.id {
            Logger.networking.debug("PlayerController: Message ignored, targeted at \(targetId, privacy: .public)")
            return false
        }

        if !gameModel.asGameMaster {
            let controls = if let authoritativeControls = model.masterState?.controls {
                authoritativeControls
            } else {
                root.gameModel.gameControl.controls
            }
            if let masterState = model.masterState,
               model.sender.isMaster,
               gameModel.shouldApplyMasterState(from: model.masterId, counter: model.counter) {
                // One MainActor hop for the whole broadcast: applying config,
                // controls and roster in separate steps lets concurrent message
                // builders capture a torn state and send it back to the master.
                // A single @MainActor function call preserves that atomicity the
                // same way `MainActor.run` did — two separate `await`-ed calls
                // would each be a scheduling point another queued task could
                // interleave between.
                applyMasterBroadcastAndResetPlayers(
                    masterId: model.masterId,
                    masterName: model.sender.name,
                    supporterTier: model.sender.supporterTier,
                    state: masterState
                )
            }

            let localId = root.gameModel.gameConfig.id
            let type = root.gameModel.gameType
            let photoSharing = root.gameModel.gameControl.features.photoSharing
            let spaceSharing = root.gameModel.gameControl.features.spaceSharing
            let dicePlayers = root.gameModel.gameControl.features.dicePlayers
            guard type == .proxy || type == .observer || controls.isEmpty || controls.contains(where: { $0.id == localId && $0.show == true }) else {
                // The controls array carries every participant's id and display
                // name — private. See CODE_AUDIT_Game §6.3.
                Logger.networking.debug("PlayerController: Message will be ignored because of controls \(controls, privacy: .private)")
                return false
            }
            // SharePlay physically broadcasts player-to-master repair requests.
            // Reject them before any module handler; only genuine player group
            // events may use the peer-to-peer presentation path.
            if !model.sender.isMaster, model.effectiveAudience == .master {
                Logger.networking.debug("PlayerController: Master-only player message ignored")
                return false
            }
            let acceptsPlayerPhotoReveal = model.isPlayerFilePresentationEvent &&
                model.data.type == .photo &&
                photoSharing
            let acceptsPlayerPdfReveal = model.isPlayerFilePresentationEvent &&
                model.data.type == .pdf
            let acceptsPlayerSpaceReveal = model.isPlayerFilePresentationEvent &&
                model.data.type == .space &&
                spaceSharing
            let acceptsPlayerDice = model.isPlayerDiceGroupEvent &&
                dicePlayers &&
                model.effectiveAudience == .group
            let acceptsPlayerMapPin = model.sender.role == .player &&
                model.type == .update &&
                model.subType == .mapPin &&
                model.data.type == .map &&
                model.effectiveAudience == .group
            let acceptsPlayerSpaceTransform = model.sender.role == .player &&
                model.type == .update &&
                model.subType == .spaceTransform &&
                model.data.type == .space &&
                spaceSharing &&
                model.effectiveAudience == .group
            guard root.gameModel.gameType == .proxy || model.sender.isMaster || acceptsPlayerDice || acceptsPlayerPhotoReveal || acceptsPlayerPdfReveal || acceptsPlayerSpaceReveal || acceptsPlayerMapPin || acceptsPlayerSpaceTransform else {
                // senderName is a participant's real display name — private. See CODE_AUDIT_Game §6.3.
                Logger.networking.debug("PlayerController: Message will be ignored because it is send from Player \(model.senderName, privacy: .private)")
                return false
            }
        }

        // Value messages synchronize the joining player's Character and are
        // not part of the presentation ordering state machine.
        if model.data.type != .value,
           (model.isPresentationIntent || model.isMapPresentationRepair) {
            let presentationVersion: Int
            let allowsUnversionedMapState: Bool
            if model.data.type == .map,
               model.type == .update,
               model.subType == .mapState {
                // Live state belongs to the currently intended Map asset. New
                // peers include the asset fingerprint; legacy peers are allowed
                // to repair the same item with an unversioned state only.
                presentationVersion = model.data.assetVersion ?? 0
                allowsUnversionedMapState = model.data.assetVersion == nil
            } else if model.data.type == .map {
                // The legacy MapModel.version covers scales only. The background
                // asset fingerprint is the presentation generation that must
                // reject a delayed Journal attachment for an older background.
                presentationVersion = model.data.effectiveAssetVersion
                allowsUnversionedMapState = false
            } else {
                presentationVersion = model.data.version
                allowsUnversionedMapState = false
            }
            let shouldProcess = gameModel.shouldProcessPresentation(
                from: model.masterId,
                senderID: model.sender.id,
                module: model.data.type,
                itemId: model.data.id,
                version: presentationVersion,
                counter: model.counter,
                timestamp: model.timestamp,
                isRepair: model.targetId != nil || model.isMapPresentationRepair,
                allowsUnversionedStateRepair: model.isTargetedMapStatePresentationRepair || allowsUnversionedMapState
            )
            guard shouldProcess else {
                Logger.networking.debug("PlayerController: Stale presentation ignored \(model.counter, privacy: .public), \(model.data.type.token, privacy: .public) id: \(model.data.id, privacy: .public)")
                return false
            }
        }

        if !event.fromProxy, event.origin != .local, !model.isAcknowledgement {
            if model.data.type != .value {
                // Proxy clients mirror this player: an answer addressed to this
                // device must be processed by them too, so clear the target before
                // forwarding. Messages targeted at other hosts were already
                // rejected above and never reach this point. Character bootstrap bypasses
                // this path and is sent directly by the proxy master controller.
                var forwarded = model
                if forwarded.targetId == root.gameModel.gameConfig.id {
                    forwarded.targetId = nil
                }
                await root.networkProxyStore.sendPlayer(data: forwarded)
            }
            await scheduleSendCharacter()
        }
        return true
    }

    func processMessages() async {
        while let event = await messagePipeline.next() {
            guard await prepareForProcessing(event) else {
                await messagePipeline.processed(success: true)
                continue
            }

            do {
                try Task.checkCancellation()
                let response = try await handle(
                    event.model,
                    usesSharePlayPlaybackCoordination: event.origin.usesSharePlayFileTransport,
                    locallyMirroredProxyPresentation: isRemappedProxyPresentation(event)
                )
                try Task.checkCancellation()
                if let response, event.origin != .local {
                    await sendUpstream(model: response)
                    if response.subType == .ok {
                        gameModel.increaseMessageCounter()
                    }
                } else {
                    gameModel.increaseMessageCounter()
                }
                await root.statisticsModel.record(
                    event.model,
                    direction: .incoming,
                    origin: event.origin
                )
                await messagePipeline.processed(success: true)
            } catch is CancellationError {
                await messagePipeline.processed(success: false)
                return
            } catch {
                // GameNetworkModel.debugDescription embeds sender.name — private. See CODE_AUDIT_Game §6.3.
                Logger.networking.error("PlayerController: Failed to process \(event.model.debugDescription, privacy: .private): \(error.localizedDescription, privacy: .public)")
                if event.origin != .local {
                    let failure = await response(for: event.model, isSuccess: false, requestData: false)
                    await sendUpstream(model: failure)
                }
                await messagePipeline.processed(success: false)
            }
        }
    }
}
