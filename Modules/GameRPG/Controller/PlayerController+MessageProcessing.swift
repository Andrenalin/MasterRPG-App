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

    func receivedProcess(_ model: GameNetworkModel, origin: GameMessageOrigin) async {
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

        // Messenger names the participant a message comes from. The one the game master
        // speaks from has no player seat at the 3D table, and a master that rejoined under
        // another participant has lost what this player announced.
        switch gameModel.noteSharePlayMasterParticipant(id: participantId) {
        case .unchanged:
            break
        case .learned:
            #if os(visionOS)
            // Seats rank players without the master once it is known. See CODE_AUDIT_18 §5.11.
            root.networkStore.sharePlayStore.masterParticipantDidChange()
            #endif
        case .changed:
            // The GroupSession can survive while the master's participant ID
            // changes. Re-announce availability and Character exactly as on a
            // fresh session so the rejoined master rebuilds its reports.
            #if os(visionOS)
            root.networkStore.sharePlayStore.masterParticipantDidChange()
            #endif
            await ready()
        }
        return true
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
        /// The message to hand to its module. A package of a presentation that is no longer
        /// the newest is stored instead of shown.
        case apply(GameNetworkModel)
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
            // Other players send their requests, reports and contributions to the game
            // master; SharePlay delivers them to everyone. Only a Dice roll, a moved pin and
            // a Space transform are for the group. This is a property of the message
            // itself, not of this device's state, so it stays a permanent rejection.
            guard type == .proxy || model.sender.isMaster || model.isPlayerGroupEvent else {
                Logger.networking.debug("PlayerController: Master-only player message ignored")
                return .rejectPermanently
            }
            let isBlockedByFeature = !model.sender.isMaster && type != .proxy && (
                (model.isDiceRollEvent && !dicePlayers) ||
                (model.data.type == .space && !spaceSharing)
            )
            // Same rationale as the controls gate above: a feature flag local to this hub
            // must not block relaying to downstream proxy clients, who may have a
            // different configuration. See CODE_AUDIT_Network §5.20.
            guard !isBlockedByFeature else {
                // senderName is a participant's real display name — private. See CODE_AUDIT_Game §6.3.
                Logger.networking.debug("PlayerController: Message will not be applied locally because it is send from Player \(model.senderName, privacy: .private)")
                await forwardToProxyClients(event)
                return .rejectLocallyOnly
            }
        }

        // What the screen shows follows the order the game master showed it in, not the
        // order it arrived in: a package can take much longer than the reference of the
        // next show. One that arrives late is kept for later, and a late reference has
        // nothing left to say.
        var applied = model
        if model.isPresentation {
            if gameModel.isCurrentPresentation(counter: model.counter, module: model.data.type, itemId: model.data.id) {
                gameModel.markPresentation(counter: model.counter, module: model.data.type, itemId: model.data.id)
                noteMasterPresentation(type: model.type, module: model.data.type, itemId: model.data.id)
            } else if model.type == .reveal, model.data.data != nil {
                applied.type = .store
                applied.subType = .store
            } else {
                Logger.networking.debug("PlayerController: Stale presentation ignored \(model.counter, privacy: .public), \(model.data.type.token, privacy: .public) id: \(model.data.id, privacy: .public)")
                return .rejectPermanently
            }
        }

        await forwardToProxyClients(event)
        return .apply(applied)
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
            let model: GameNetworkModel
            switch await prepareForProcessing(event) {
            case .rejectPermanently:
                await messagePipeline.processed(success: true)
                continue
            case .rejectLocallyOnly:
                await messagePipeline.processed(success: false)
                continue
            case .apply(let applied):
                model = applied
            }

            do {
                try Task.checkCancellation()
                let response = try await handle(
                    model,
                    usesSharePlayPlaybackCoordination: event.origin.usesSharePlayFileTransport
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
                Logger.networking.error("PlayerController: Failed to process \(event.model.debugDescription, privacy: .private): \(error.logIdentifier, privacy: .public) \(error.localizedDescription, privacy: .private)")
                if event.origin != .local {
                    let failure = await response(for: event.model, isSuccess: false, requestData: false)
                    await sendUpstream(model: failure)
                }
                await messagePipeline.processed(success: false)
            }
        }
    }
}
