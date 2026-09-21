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

// MARK: - MasterNetworkStoreDelegate
// Conformance itself is declared alongside the class in MasterController.swift (Swift requires
// same-file `Sendable` conformance for a class); this extension supplies the requirements.

extension MasterController {
    func accepts(_ model: GameNetworkModel, origin: GameMessageOrigin) async -> Bool {
        let expectedMasterId = root.gameModel.gameConfig.master.id

        // Every message entering the master's receive side came from a remote
        // player transport. A remote endpoint can never acquire authority by
        // changing only its encoded role or by reusing the master's sender ID.
        guard !model.sender.isMaster,
              model.sender.id != expectedMasterId,
              model.masterState == nil
        else {
            Logger.networking.debug("MasterController: Rejected remote master claim from \(model.sender.id, privacy: .public)")
            return false
        }

        guard acceptsTransportRole(model.sender.role, origin: origin) else {
            Logger.networking.debug("MasterController: Rejected \(String(describing: model.sender.role), privacy: .public) sender on incompatible transport")
            return false
        }

        // Players do not know the master's UUID before the first authoritative
        // response. Preserve only the exact master-only bootstrap packets sent
        // at join; every gameplay/peer-visible event must already name this
        // session's master.
        guard model.masterId == expectedMasterId || Self.isPlayerBootstrapEnvelope(model) else {
            Logger.networking.debug("MasterController: Rejected message for another master \(model.masterId, privacy: .public)")
            return false
        }

        guard !model.isPlayerFilePresentationEvent ||
                GameNetworkModel.acceptsEventTimestamp(model.timestamp)
        else {
            Logger.networking.debug("MasterController: Rejected player presentation with invalid timestamp")
            return false
        }

        if model.isJournalAdmissionOnly {
            guard case .sharePlay = origin else {
                Logger.networking.debug("MasterController: Rejected Journal admission on a non-SharePlay transport")
                return false
            }
        }

        if let connectionId = origin.participantConnectionId {
            guard gameModel.accepts(
                connectionId: connectionId,
                sender: model.sender
            ) else { return false }

            // A player Journal attachment has no physical source identity.
            // Admit its exact fingerprint only after the same message arrives
            // through participant-attributed SharePlay Messenger.
            if case .sharePlay = origin,
               model.isPlayerJournalAdmissionMetadata {
                guard gameModel.admitPlayerJournalMetadata(model) else {
                    Logger.networking.debug("MasterController: Rejected conflicting player Journal admission")
                    return false
                }
            }
            return true
        }

        if origin == .file {
            guard gameModel.acceptsPlayerJournal(model) else {
                Logger.networking.debug("MasterController: Rejected uncorrelated Journal sender \(model.sender.id, privacy: .public)")
                return false
            }
        }
        return true
    }

    /// Transport topology is part of sender authority, not merely a routing
    /// detail. Bonjour players and observers connect to the main master;
    /// SharePlay and Journal accept only players; private LAN mirrors connect
    /// only to the host player's proxy master.
    private nonisolated func acceptsTransportRole(
        _ role: GameType,
        origin: GameMessageOrigin
    ) -> Bool {
        switch (asProxy, origin) {
        case (false, .direct(_)):
            role == .player || role == .observer
        case (false, .sharePlay(_)), (false, .file):
            role == .player
        case (true, .proxy(_)):
            role == .proxy
        case (false, .proxy(_)), (false, .local),
             (true, .direct(_)), (true, .sharePlay(_)),
             (true, .file), (true, .local):
            false
        }
    }

    private nonisolated static func isPlayerBootstrapEnvelope(_ model: GameNetworkModel) -> Bool {
        guard model.sender.role == .player ||
                model.sender.role == .observer ||
                model.sender.role == .proxy,
              model.effectiveAudience == .master
        else { return false }

        switch (model.type, model.subType, model.data.type) {
        case (.update, .audioList, .audio),
             (.update, .photoList, .photo),
             (.update, .pdfList, .pdf),
             (.update, .spaceList, .space),
             (.update, .store, .value),
             (.store, .store, .setting):
            return true
        default:
            return false
        }
    }

    func ready(for origin: GameMessageOrigin) async {
        Logger.networking.debug("MasterController: Participant ready")
        if let participantId = origin.sharePlayParticipantId {
            // GroupSession can reissue this participant's UUID to the same
            // device after a crash/relaunch rejoin. Trust only this
            // OS-confirmed join to clear an earlier retirement so the
            // reconnected player's messages bind again instead of being
            // rejected forever.
            gameModel.reinstateConnection(participantId)
        }
        await replayCurrentPresentation(to: origin)
    }

    func lostPlayer(for connectionId: ConnectionController.ID) async {
        Logger.networking.debug("MasterController: Lost Player for \(connectionId, privacy: .public)")
        guard let playerId = gameModel.remove(connectionId: connectionId) else { return }
        root.audioRoot.gameControllable.gameModel.removePlayerReport(for: playerId)
        root.photoRoot.photoGameControllable.removePhotoReports(for: playerId)
        root.pdfRoot.pdfGameControllable.removePdfReports(for: playerId)
        root.spaceRoot.spaceGameControllable.removeSpaceReports(for: playerId)
        root.tableRoot.gameControllable.gameModel.removePlayerReport(for: playerId)
        root.weatherRoot.gameControllable.gameModel.removePlayerReport(for: playerId)
        if root.gameModel.remove(playerId: playerId) {
            await root.statisticsModel.participantLeft(id: playerId)
            await resetPlayers()
        }
    }

    func received(_ model: GameNetworkModel, connectionId: ConnectionController.ID?) async {
        await receivedProcess(model, connectionId: connectionId)
    }

    func received(_ model: GameNetworkModel, origin: GameMessageOrigin) async {
        await receivedProcess(model, origin: origin)
    }

    func receivedProcess(_ model: GameNetworkModel, connectionId: ConnectionController.ID?) async {
        await receivedProcess(model, origin: .direct(connectionId))
    }

    /// Not `private` because `MasterController+ProxyDelegate.swift`'s
    /// `receivedServerProxy(_:connectionId:)` also calls this directly, from a
    /// different file.
    func receivedProcess(_ model: GameNetworkModel, origin: GameMessageOrigin) async {
        Logger.networking.debug("MasterController: Received \(model.counter, privacy: .public): \(model.type.debugDescription, privacy: .public) - \(model.subType.debugDescription, privacy: .public), \(model.data.type.token, privacy: .public) id: \(model.data.id, privacy: .public)")

        guard await accepts(model, origin: origin) else { return }

        if model.isPlayerJournalAdmissionMetadata,
           let pendingFile = gameModel.takeDeferredPlayerJournalFile(senderId: model.sender.id, messageId: model.messageID) {
            // This admission metadata is exactly what an earlier file event
            // was waiting to be correlated against — replay it now instead
            // of leaving it lost. See CODE_AUDIT_Network §5.16.
            await receivedFile(pendingFile)
        }

        let event = GameMessageEvent(model: model, origin: origin)
        switch await messagePipeline.enqueue(event) {
        case .enqueued:
            await processMessages()
        case .duplicate:
            Logger.networking.debug("MasterController: Duplicate ignored \(model.counter, privacy: .public): \(model.type.debugDescription, privacy: .public) - \(model.subType.debugDescription, privacy: .public), \(model.data.type.token, privacy: .public)")
        case .queueFull:
            // Distinct from an ordinary duplicate: a genuinely new message
            // was discarded only because the pipeline is momentarily
            // saturated, not because it was already seen. See
            // CODE_AUDIT_Network §5.14.
            Logger.networking.error("MasterController: Message queue full, message lost \(model.counter, privacy: .public): \(model.type.debugDescription, privacy: .public) - \(model.subType.debugDescription, privacy: .public), \(model.data.type.token, privacy: .public)")
        case .pipelineStopped:
            Logger.networking.debug("MasterController: Message pipeline stopped, ignoring \(model.counter, privacy: .public)")
        }
    }

    private func processMessages() async {
        while let event = await messagePipeline.next() {
            // Bail out before any processing is attempted, so the one
            // message `next()` already dequeued isn't lost: `processed(success:)`
            // only clears bookkeeping, it never restores the event to the
            // queue. `requeueCurrentOnCancellation()` puts it back at the
            // front so the next real trigger resumes the backlog, matching
            // PlayerController.processMessages' policy. See
            // CODE_AUDIT_Network §5.15 (superseding CODE_AUDIT_Game §3.8's
            // inaccurate claim that the old `processed(success: false)` call
            // already preserved the in-hand event).
            guard !Task.isCancelled else {
                await messagePipeline.requeueCurrentOnCancellation()
                await handOffBacklog()
                return
            }
            let success = await process(event)
            await messagePipeline.processed(success: success)
        }
    }

    /// The drain runs inside whichever peer's receive task enqueued first, so cancelling that
    /// peer (teardown) must not strand the other peers' queued messages: continue the drain on
    /// a fresh task. If the cancellation was a genuine stop the pipeline was already reset and
    /// the new drain finds no work. See CODE_AUDIT_16 §3.2.
    private func handOffBacklog() async {
        guard await messagePipeline.hasQueuedMessages else { return }
        Task { [weak self] in
            await self?.processMessages()
        }
    }

    private func process(_ event: GameMessageEvent) async -> Bool {
        let receivedModel = event.model

        // Before the roster add: a proxy client is a private mirror of the host
        // player and must never appear as a player of its own — not in the
        // host's roster and never upstream at the master.
        if asProxy {
            let success = await processAsProxy(receivedModel, connectionId: event.connectionId)
            if success {
                await root.statisticsModel.record(receivedModel, direction: .incoming, origin: event.origin)
            }
            return success
        }

        if !receivedModel.sender.isMaster, receivedModel.sender.role != .notSet {
            if root.gameModel.add(playerId: receivedModel.sender.id, playerModel: receivedModel.sender.playerModel, sharingModel: SharingControlModel(id: receivedModel.sender.id, name: receivedModel.sender.name, show: true)) {
                await resetPlayers()
            }
        }

        guard let model = normalizedObserverMessage(receivedModel) else {
            // GameNetworkModel.debugDescription embeds sender.name — private. See CODE_AUDIT_Game §6.3.
            Logger.networking.debug("MasterController: Observer action ignored \(receivedModel.debugDescription, privacy: .private)")
            return true
        }

        if await shouldTrackPeerAvailabilitySource(model) {
            let recipients = root.logGameController.recipientIDs()
            gameModel.trackPeerAvailabilitySource(
                model,
                recipients: recipients
            )
        }

        let masterDeliveryAuthorizesAvailability = await recordDeliveryReceipt(model)
        if model.subType == .ok {
            let peerPresentationAuthorizesAvailability = if masterDeliveryAuthorizesAvailability {
                false
            } else {
                gameModel.acceptsPeerAvailabilityReceipt(model)
            }
            guard masterDeliveryAuthorizesAvailability || peerPresentationAuthorizesAvailability else {
                Logger.networking.debug("MasterController: Ignored uncorrelated availability acknowledgement from \(model.sender.id, privacy: .public)")
                await root.statisticsModel.record(model, direction: .incoming, origin: event.origin)
                return true
            }
        }

        do {
            try Task.checkCancellation()
            if let requestedData = try await handle(model, origin: event.origin) {
                try Task.checkCancellation()
                if requestedData.data != nil, requestedData.type != .map {
                    // The full payload went out — a later reshow can rely on
                    // the reference no matter which path delivered first.
                    // Map is deliberately excluded: all Map request responses
                    // are requester-only repairs (including photo-free generic
                    // updates). Only show(for:) publishes the full Map package
                    // to the group and may establish the shared sent baseline.
                    gameModel.markSentGameItem(type: requestedData.type, id: requestedData.id, version: requestedData.effectiveAssetVersion)
                }
                // Target the answer at the requester: an untargeted full payload
                // re-triggered "show" on every peer and flipped everyone's screen.
                await send(
                    type: model.type,
                    subtype: model.subType,
                    updated: requestedData,
                    origin: event.origin,
                    playerId: model.sender.id
                )
            }
            await root.statisticsModel.record(model, direction: .incoming, origin: event.origin)
            return true
        } catch is CancellationError {
            return false
        } catch {
            // GameNetworkModel.debugDescription embeds sender.name — private. See CODE_AUDIT_Game §6.3.
            Logger.networking.error("MasterController: Failed to process \(model.debugDescription, privacy: .private): \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private func shouldTrackPeerAvailabilitySource(
        _ model: GameNetworkModel
    ) async -> Bool {
        guard model.isPlayerFilePresentationEvent,
              GameNetworkModel.acceptsEventTimestamp(model.timestamp)
        else { return false }

        let baseline: Int
        switch model.data.type {
        case .photo:
            guard root.gameModel.gameControl.features.photoSharing else {
                return false
            }
            baseline = await root.photoRoot.gameControllable.networkVersion(
                for: model.data.id
            )
        case .pdf:
            baseline = await root.pdfRoot.gameControllable.networkVersion(
                for: model.data.id
            )
        case .space:
            guard root.gameModel.gameControl.features.spaceSharing else {
                return false
            }
            baseline = await root.spaceRoot.gameControllable.networkVersion(
                for: model.data.id
            )
        default:
            return false
        }
        return model.data.effectiveAssetVersion == baseline
    }

    /// Records every valid delivery acknowledgement, and returns whether the
    /// original master packet is a file-bearing reveal/store whose receipt may
    /// also update an asset-availability report.
    private func recordDeliveryReceipt(_ model: GameNetworkModel) async -> Bool {
        // A failed transfer and a request for missing bytes both prove the
        // opposite of delivery. Only an explicit successful acknowledgement
        // may complete the master's delivery row.
        guard model.subType == .ok else { return false }

        let deliveryID: GameDeliveryMessageID?
        if let replyToMessageID = model.replyToMessageID {
            deliveryID = gameModel.deliveryMessageID(replyingTo: replyToMessageID)
        } else if model.messageID == nil {
            // V1 has no stable wire identity. Retain its counter compatibility,
            // but only for an exact module/item receipt shape.
            deliveryID = root.gameModel.logData[model.counter]?.messageID
        } else {
            deliveryID = nil
        }

        guard let deliveryID else { return false }
        let deliveryMatch: (matches: Bool, authorizesAvailability: Bool)
        if let log = root.gameModel.logData[deliveryID.counter] {
            let matches = log.messageID == deliveryID &&
                log.type == model.type &&
                log.module == model.data.type &&
                log.itemId == model.data.id
            deliveryMatch = (
                matches: matches,
                authorizesAvailability: matches &&
                    (log.type == .reveal || log.type == .store)
            )
        } else {
            deliveryMatch = (matches: false, authorizesAvailability: false)
        }
        guard deliveryMatch.matches else { return false }

        let recorded = root.logGameController.updateMessage(
            messageID: deliveryID,
            player: model.sender.id
        )
        return recorded && deliveryMatch.authorizesAvailability
    }

    /// Observers participate in availability/repair handshakes but cannot issue
    /// gameplay actions. This is enforced again here even though the LAN bridge
    /// already refuses to relay observer group events.
    func normalizedObserverMessage(_ model: GameNetworkModel) -> GameNetworkModel? {
        guard model.sender.role == .observer else { return model }
        if model.isAcknowledgement { return model }

        // Reports and screen samples are safe only in their exact protocol
        // envelopes. Checking the subtype alone lets an observer pair a benign
        // action such as `.photoList` or `.screen` with `.reveal`, which then
        // enters a file-backed module's presentation path.
        switch (model.type, model.subType, model.data.type) {
        case (.update, .audioList, .audio),
             (.update, .photoList, .photo),
             (.update, .pdfList, .pdf),
             (.update, .spaceList, .space),
             (.store, .screen, .game):
            guard model.data.data != nil else { return nil }
            return model
        default:
            break
        }

        // An observer is a passive local-network display. It may name a missing
        // asset, but it can never upload bytes or disguise a gameplay action as
        // an asset request. Legacy data-less repair envelopes are normalized so
        // module handlers take their requester-only paths instead of presenting
        // the item to the group.
        guard model.data.data == nil,
              model.purpose == .assetRequest || model.purpose == .legacy
        else { return nil }

        let isPassiveAsset = switch model.data.type {
        case .audio, .dice, .map, .pdf, .photo, .space, .table, .weather:
            true
        default:
            false
        }
        guard isPassiveAsset else { return nil }

        let isRepairShape = switch (model.type, model.subType) {
        case (.reveal, .show), (.store, .store):
            true
        case (.reveal, .mapState):
            model.data.type == .map
        case (.update, .generic):
            model.data.type == .map
        default:
            false
        }
        guard isRepairShape else { return nil }

        var request = model
        request.purpose = .assetRequest
        request.audience = .master
        return request
    }

    func receivedFile(_ model: GameNetworkModel) async {
        Logger.networking.debug("MasterController: FILE Received \(model.counter, privacy: .public): \(model.type.debugDescription, privacy: .public) - \(model.subType.debugDescription, privacy: .public), \(model.data.type.token, privacy: .public) id: \(model.data.id, privacy: .public)")
        guard root.gameModel.gameConfig.isMaster != model.sender.isMaster else { return }
        guard await accepts(model, origin: .file) else {
            // GroupSessionJournal attachments and GroupSessionMessenger
            // messages are independent channels with no cross-channel
            // ordering guarantee: this file's matching admission metadata
            // may simply not have been processed yet. Hold it and replay it
            // once that admission lands (see `receivedProcess`'s replay
            // hook) instead of losing this Photo/Pdf/Space permanently.
            // See CODE_AUDIT_Network §5.16.
            if model.isPlayerFilePresentationEvent,
               model.messageID != nil,
               !gameModel.acceptsPlayerJournal(model) {
                gameModel.deferUnmatchedPlayerJournalFile(model)
            }
            return
        }
        switch await messagePipeline.enqueue(GameMessageEvent(model: model, origin: .file)) {
        case .enqueued:
            await processMessages()
        case .duplicate:
            Logger.networking.debug("MasterController: Duplicate file ignored \(model.counter, privacy: .public): \(model.type.debugDescription, privacy: .public) - \(model.subType.debugDescription, privacy: .public), \(model.data.type.token, privacy: .public)")
        case .queueFull:
            Logger.networking.error("MasterController: Message queue full, file message lost \(model.counter, privacy: .public): \(model.type.debugDescription, privacy: .public) - \(model.subType.debugDescription, privacy: .public), \(model.data.type.token, privacy: .public)")
        case .pipelineStopped:
            Logger.networking.debug("MasterController: Message pipeline stopped, ignoring file \(model.counter, privacy: .public)")
        }
    }
}
