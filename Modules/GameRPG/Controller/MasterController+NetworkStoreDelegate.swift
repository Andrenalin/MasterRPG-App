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
    /// The checks every inbound message passes before it is relayed or processed. They need
    /// nothing from the sender but the envelope: a remote peer can never be the master, its
    /// role has to fit the transport it uses, it has to name this game's master, and a
    /// connection speaks for one player only.
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

        // Players do not know the master's UUID before the first master
        // message. Only the packets a player sends at join may come without it.
        guard model.masterId == expectedMasterId || Self.isPlayerBootstrapEnvelope(model) else {
            Logger.networking.debug("MasterController: Rejected message for another master \(model.masterId, privacy: .public)")
            return false
        }

        return store.model.playerRoutes.bind(origin, to: model.sender)
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
              model.targetId == nil
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

    func mayRelay(_ model: GameNetworkModel, origin: GameMessageOrigin) async -> Bool {
        if await messagePipeline.hasSeen(GameMessageEvent(model: model, origin: origin)) {
            return false
        }
        if model.isDiceRollEvent {
            guard root.gameModel.gameControl.features.dicePlayers else { return false }
            if let reported = DiceResultModel.decodeData(of: model.data.data), !reported.isPlausibleReport {
                Logger.networking.warning("MasterController: Dice roll from \(model.sender.id, privacy: .public) not relayed — implausible roll")
                return false
            }
        }
        if model.subType == .spaceTransform, model.data.type == .space {
            guard root.spaceRoot.spaceGameControllable.isValidSpaceTransform(model.data),
                  root.spaceRoot.gameControllable.gameModel.currentItemId == model.data.id
            else { return false }
        }
        // Last, in one step: a copy that is handled at the same time passes the checks above
        // too, and only one of them may relay.
        return await messagePipeline.reserveRelay(GameMessageEvent(model: model, origin: origin))
    }

    func ready(for origin: GameMessageOrigin) async {
        Logger.networking.debug("MasterController: Participant ready")
        if let participantId = origin.sharePlayParticipantId {
            // GroupSession can reissue this participant's UUID to the same
            // device after a crash/relaunch rejoin. Trust only this
            // OS-confirmed join to clear an earlier retirement so the
            // reconnected player's messages bind again instead of being
            // rejected forever.
            store.model.playerRoutes.reinstate(connectionId: participantId)
        }
        await replayCurrentPresentation(to: origin)
    }

    func lostPlayer(for connectionId: ConnectionController.ID) async {
        Logger.networking.debug("MasterController: Lost Player for \(connectionId, privacy: .public)")
        guard let playerId = store.model.playerRoutes.remove(connectionId: connectionId) else { return }
        gameModel.forget(playerId: playerId)
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

        // The connection may have been lost while this message waited in the queue. A processed
        // message adds its sender to the roster, so one from a lost player would bring back an
        // entry with no connection behind it. See CODE_AUDIT_23 §5.4.
        guard store.model.playerRoutes.isBound(event.origin, to: receivedModel.sender.id) else {
            Logger.networking.debug("MasterController: Dropped queued message from a lost connection \(receivedModel.counter, privacy: .public)")
            return true
        }

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

        // An acknowledgement that answers no message this game sent says nothing.
        if model.subType == .ok, !recordDeliveryReceipt(model) {
            Logger.networking.debug("MasterController: Ignored uncorrelated acknowledgement from \(model.sender.id, privacy: .public)")
            await root.statisticsModel.record(model, direction: .incoming, origin: event.origin)
            return true
        }

        do {
            try Task.checkCancellation()
            if let requestedData = try await handle(model, origin: event.origin) {
                try Task.checkCancellation()
                // The answer to a request: it keeps the counter of the message the player
                // could not use, and goes back the way the request came. A request that
                // echoes no master message (a pin photo of a map) has counter 0 and is
                // answered under a new one, so the answer is logged and never processed
                // twice. A package is not addressed to the requester alone: over the
                // SharePlay Journal it reaches everyone, and whoever lacks it as well
                // takes it.
                await send(
                    type: model.type,
                    subtype: model.subType,
                    updated: requestedData,
                    counter: model.isAssetRequest && model.counter > 0 ? model.counter : nil,
                    origin: event.origin,
                    playerId: requestedData.carriesAsset ? nil : model.sender.id
                )
            }
            await root.statisticsModel.record(model, direction: .incoming, origin: event.origin)
            return true
        } catch is CancellationError {
            return false
        } catch {
            // GameNetworkModel.debugDescription embeds sender.name — private. See CODE_AUDIT_Game §6.3.
            Logger.networking.error("MasterController: Failed to process \(model.debugDescription, privacy: .private): \(error.logIdentifier, privacy: .public) \(error.localizedDescription, privacy: .private)")
            return false
        }
    }

    /// Marks the acknowledging player in the log row of the message it answers, found by the
    /// echoed counter. Returns whether the acknowledgement belongs to a reveal or store of
    /// this game, which is what lets it update an availability report.
    private func recordDeliveryReceipt(_ model: GameNetworkModel) -> Bool {
        guard let log = root.gameModel.logData[model.counter],
              log.messageID.sessionID == gameModel.deliverySessionID,
              log.module == model.data.type,
              log.itemId == model.data.id
        else { return false }

        root.logGameController.updateMessage(messageID: log.messageID, player: model.sender.id)
        return log.type == .reveal || log.type == .store
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
        case (.update, .mapPin, .map):
            // Moving a player pin the game master gave this observer; `handleMap` admits it
            // only for such a pin. See `MapPinModel.isControlled(by:)`.
            guard model.data.data != nil else { return nil }
            return model
        default:
            break
        }

        // An observer is a passive local-network display. It may ask for an item it lacks,
        // but it can never upload bytes or issue a gameplay action.
        return model.isAssetRequest ? model : nil
    }

    func receivedFile(_ model: GameNetworkModel) async {
        Logger.networking.debug("MasterController: FILE Received \(model.counter, privacy: .public): \(model.type.debugDescription, privacy: .public) - \(model.subType.debugDescription, privacy: .public), \(model.data.type.token, privacy: .public) id: \(model.data.id, privacy: .public)")
        guard root.gameModel.gameConfig.isMaster != model.sender.isMaster else { return }
        guard await accepts(model, origin: .file) else { return }
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
