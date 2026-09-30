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

// The incoming-message pipeline, split out of PlayerController+NetworkStoreDelegate.swift —
// see CODE_AUDIT_19 §9.23.

extension PlayerController {
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
        switch await messagePipeline.enqueue(GameMessageEvent(model: model, origin: origin)) {
        case .enqueued:
            await processMessages()
        case .duplicate:
            Logger.networking.debug("PlayerController: Duplicate ignored \(model.counter, privacy: .public): \(model.type.debugDescription, privacy: .public) - \(model.subType.debugDescription, privacy: .public), \(model.data.type.token, privacy: .public)")
        case .queueFull:
            // Distinct from an ordinary duplicate: a genuinely new message
            // was discarded only because the pipeline is momentarily
            // saturated, not because it was already seen. See
            // CODE_AUDIT_Network §5.14.
            Logger.networking.error("PlayerController: Message queue full, message lost \(model.counter, privacy: .public): \(model.type.debugDescription, privacy: .public) - \(model.subType.debugDescription, privacy: .public), \(model.data.type.token, privacy: .public)")
        case .pipelineStopped:
            Logger.networking.debug("PlayerController: Message pipeline stopped, ignoring \(model.counter, privacy: .public)")
        }
    }

    /// Establishes authority from the first complete master broadcast and then
    /// pins every remote envelope to that session. A locally remapped proxy
    /// presentation is already authenticated by the proxy host controller.
    func acceptsSessionMessage(
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
        case .alreadyBound:
            return true
        case .newlyBound:
            #if os(visionOS)
            // Seats rank players without the master once it is known. See CODE_AUDIT_18 §5.11.
            root.networkStore.sharePlayStore.masterParticipantDidChange()
            #endif
            return true
        case .rebound:
            // The GroupSession can survive while the master's participant ID
            // changes. Re-announce availability and Character exactly as on a
            // fresh session so the rejoined master rebuilds its reports.
            #if os(visionOS)
            root.networkStore.sharePlayStore.masterParticipantDidChange()
            #endif
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

    /// Outcome of `prepareForProcessing`, keeping two independent questions
    /// from being conflated the way a single `Bool` previously did: whether a
    /// rejection is permanent (safe to remember as "already handled", like an
    /// out-of-session target or a genuinely stale presentation) versus
    /// transient (this device's own local policy — roster visibility, a
    /// feature flag — currently blocks *local* application, but the message
    /// itself is still valid and must stay retry-eligible so a later
    /// redelivery isn't silently deduped away once the condition clears).
    /// See CODE_AUDIT_Network §5.22.
    private enum ProcessingDecision {
        case rejectPermanently
        case rejectLocallyOnly
        case apply
    }

    private func prepareForProcessing(_ event: GameMessageEvent) async -> ProcessingDecision {
        let model = event.model

        // Targeted messages are only processed by the addressee. Proxy clients
        // are deliberately invisible upstream and every proxy request is remapped
        // to its host ID, so a target belonging to another host can never live
        // behind this device.
        if let targetId = model.targetId, targetId != root.gameModel.gameConfig.id {
            Logger.networking.debug("PlayerController: Message ignored, targeted at \(targetId, privacy: .public)")
            return .rejectPermanently
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
            // This hub's own roster visibility gates whether the message is
            // applied to *this* device's local state, not whether it's valid.
            // A proxy-connected player behind this hub has entirely separate
            // roster/visibility state, so the message still needs forwarding
            // to them even when it's not applied here. See CODE_AUDIT_Network
            // §5.20.
            guard type == .proxy || type == .observer || controls.isEmpty || controls.contains(where: { $0.id == localId && $0.show == true }) else {
                // The controls array carries every participant's id and display
                // name — private. See CODE_AUDIT_Game §6.3.
                Logger.networking.debug("PlayerController: Message will not be applied locally because of controls \(controls, privacy: .private)")
                await forwardToProxyClients(event)
                return .rejectLocallyOnly
            }
            // SharePlay physically broadcasts player-to-master repair requests.
            // Reject them before any module handler; only genuine player group
            // events may use the peer-to-peer presentation path. This is a
            // property of the message's own addressing, not of this device's
            // local state, so it stays a permanent rejection.
            if !model.sender.isMaster, model.effectiveAudience == .master {
                Logger.networking.debug("PlayerController: Master-only player message ignored")
                return .rejectPermanently
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
            // Same rationale as the controls gate above: a per-feature flag
            // local to this hub (dicePlayers/photoSharing/spaceSharing) must
            // not block relaying to downstream proxy clients, who may have a
            // different configuration. See CODE_AUDIT_Network §5.20.
            guard root.gameModel.gameType == .proxy || model.sender.isMaster || acceptsPlayerDice || acceptsPlayerPhotoReveal || acceptsPlayerPdfReveal || acceptsPlayerSpaceReveal || acceptsPlayerMapPin || acceptsPlayerSpaceTransform else {
                // senderName is a participant's real display name — private. See CODE_AUDIT_Game §6.3.
                Logger.networking.debug("PlayerController: Message will not be applied locally because it is send from Player \(model.senderName, privacy: .private)")
                await forwardToProxyClients(event)
                return .rejectLocallyOnly
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
                return .rejectPermanently
            }
        }

        await forwardToProxyClients(event)
        return .apply
    }

    /// Mirrors a valid group/master message to this device's own downstream
    /// proxy clients, independent of whether the message was also applied to
    /// this device's own local state. See CODE_AUDIT_Network §5.20.
    private func forwardToProxyClients(_ event: GameMessageEvent) async {
        let model = event.model
        guard !event.fromProxy, event.origin != .local, !model.isAcknowledgement else { return }
        if model.data.type != .value {
            // Proxy clients mirror this player: an answer addressed to this
            // device must be processed by them too, so clear the target before
            // forwarding. Messages targeted at other hosts were already
            // rejected before this point. Character bootstrap bypasses
            // this path and is sent directly by the proxy master controller.
            var forwarded = model
            if forwarded.targetId == root.gameModel.gameConfig.id {
                forwarded.targetId = nil
            }
            await root.networkProxyStore.sendPlayer(data: forwarded)
        }
        await scheduleSendCharacter()
    }

    func processMessages() async {
        while let event = await messagePipeline.next() {
            // Bail out before any processing is attempted, so the one
            // message `next()` already dequeued isn't lost. Safe only here,
            // before `prepareForProcessing` (which can itself have side
            // effects, e.g. forwarding to proxy clients) has run — the
            // deeper `catch is CancellationError` below, after those side
            // effects may have already happened, deliberately keeps its
            // existing non-requeueing behavior to avoid re-applying them.
            // See CODE_AUDIT_Network §5.15.
            guard !Task.isCancelled else {
                await messagePipeline.requeueCurrentOnCancellation()
                // This loop is the only caller of `processMessages()`; without this, a
                // message requeued here would strand until an unrelated future message
                // happens to re-trigger `.enqueued`. If the ambient Task was cancelled by
                // a genuine teardown, `messagePipeline` was also `cancelAll()`'d/`reset()`,
                // so `next()` on this fresh Task will simply see no work and return. See
                // CODE_AUDIT.md §3.4.
                if await messagePipeline.hasQueuedMessages {
                    Task { [weak self] in
                        await self?.processMessages()
                    }
                }
                return
            }
            switch await prepareForProcessing(event) {
            case .rejectPermanently:
                await messagePipeline.processed(success: true)
                continue
            case .rejectLocallyOnly:
                await messagePipeline.processed(success: false)
                continue
            case .apply:
                break
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
                // The in-hand event is dropped on purpose (its side effects may have run), but
                // the rest of the backlog must not strand. See CODE_AUDIT_16 §3.2.
                if await messagePipeline.hasQueuedMessages {
                    Task { [weak self] in
                        await self?.processMessages()
                    }
                }
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
