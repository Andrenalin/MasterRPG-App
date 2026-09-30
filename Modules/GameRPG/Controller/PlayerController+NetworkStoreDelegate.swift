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
        // `acceptsSessionMessage` only re-pins the logical master identity
        // from a self-consistent full broadcast while `config.master.type`
        // is still `.notSet` — once pinned to `.master` it requires an exact
        // `masterId` match forever. A master that fully quits and restarts
        // (`GameRoot.startMaster()` mints a brand-new `master.id` per
        // session) reconnects under a different id than what this device
        // still has pinned, so without unpinning here every message from
        // the restarted master — and, since `ready()` never re-fires the
        // handshake broadcast that would otherwise repin it, every message
        // this device sends back — is silently rejected forever even though
        // the transport layer reports a successful reconnect. Reverting to
        // `.notSet` re-opens the one-time discovery window so the next full
        // master broadcast can re-establish authority under its new id.
        root.gameModel.gameConfig.master.type = .notSet
        // GameMessageKey carries no session-generation nonce. Without this,
        // a rejoined session replaying/rebuilding low-numbered messages (a
        // fresh master session, or a SharePlay Journal catch-up for a
        // rejoining participant) could collide with keys this device still
        // remembers from before the drop and be silently deduped away, even
        // though every other piece of per-connection state was just reset
        // above. See CODE_AUDIT_Network §5.21.
        await messagePipeline.reset()
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
        guard receivesOppositeRole || model.isPlayerFilePresentationEvent else {
            Logger.networking.debug("PlayerController: FILE rejected \(model.counter, privacy: .public), same-role non-player-presentation traffic")
            return
        }
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
        guard receivesOppositeRole || model.isPlayerFilePresentationEvent else {
            Logger.networking.debug("PlayerController: SharePlay FILE rejected \(model.counter, privacy: .public), same-role non-player-presentation traffic")
            return
        }
        await receivedProcess(model, origin: .file)
    }

    func isPinnedSharePlayMasterParticipant(id: UUID) async -> Bool {
        gameModel.isSharePlayMasterParticipant(id: id)
    }

    func sharePlayFileLoadFailed(_ model: GameNetworkModel) async {
        guard model.sender.isMaster,
              !root.gameModel.gameConfig.isMaster,
              await acceptsSessionMessage(model, origin: .file)
        else {
            Logger.networking.debug("PlayerController: SharePlay file-load-failure ignored \(model.counter, privacy: .public), sender/role/session check failed")
            return
        }

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
}
