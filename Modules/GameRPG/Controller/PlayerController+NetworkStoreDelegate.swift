// @copyright André Trettin

import AudioRPG
import CoreRPG
import Foundation
import os.log
import MapRPG
import PdfRPG
import PhotoRPG
import SpaceRPG
#if os(macOS)
#else
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
        // The model forgot the photo, so the popover that shows it must go too: its Close button
        // has nothing left to close.
        root.mapRoot.photoPopover.photo = nil
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
        await sendFileLists()
        await scheduleSendCharacter()
    }

    func receivedFile(_ model: GameNetworkModel) async {
        Logger.networking.debug("PlayerController: FILE Received \(model.counter, privacy: .public): \(model.type.debugDescription, privacy: .public) - \(model.subType.debugDescription, privacy: .public), \(model.data.type.token, privacy: .public) id: \(model.data.id, privacy: .public)")
        // A file is for the other role: the game master's for the players, a player's for
        // the game master.
        guard root.gameModel.gameConfig.isMaster != model.sender.isMaster else {
            Logger.networking.debug("PlayerController: FILE rejected \(model.counter, privacy: .public), same-role traffic")
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

    func receivedSharePlayFile(_ model: GameNetworkModel) async {
        await receivedFile(model)
    }

    func isSharePlayMasterParticipant(id: UUID) async -> Bool {
        gameModel.isSharePlayMasterParticipant(id: id)
    }

    /// The file of an audio, photo, PDF or 3D object the game master published is already here
    /// (the reference was handled before this attachment was looked at).
    func sharePlayHoldsFile(_ model: GameNetworkModel) async -> Bool {
        guard model.sender.isMaster, !root.gameModel.gameConfig.isMaster else { return false }
        let controllable: any GameControllable
        switch model.data.type {
        case .audio: controllable = root.audioRoot.gameControllable
        case .photo: controllable = root.photoRoot.gameControllable
        case .pdf: controllable = root.pdfRoot.gameControllable
        case .space: controllable = root.spaceRoot.gameControllable
        default: return false
        }
        return await holdsFile(of: model.data, in: controllable)
    }

    /// The Journal named a file of the game master but its bytes did not load. The message is
    /// handled like its reference: an item this device already holds is shown, anything else
    /// is asked for with the same counter. (An audio is reported as failed instead.) The game master does not upload a file again for
    /// the show it already uploaded it for; it does once the item is shown again later.
    func sharePlayFileLoadFailed(_ model: GameNetworkModel) async {
        guard model.sender.isMaster, !root.gameModel.gameConfig.isMaster else {
            Logger.networking.debug("PlayerController: SharePlay file-load-failure ignored \(model.counter, privacy: .public), sender/role check failed")
            return
        }
        if model.data.type == .audio {
            // The reference of this show was handled when it arrived, so the pipeline would drop
            // this message as a repeat of it. The game master's play waits for this player's
            // file: it must learn that the file did not arrive, to send it again a bounded
            // number of times and then go on without this player. A player that already holds
            // the file answered Ok when the reference arrived; the Journal copy it could not
            // load is redundant for it, and a failure would make the master send it again.
            if await holdsFile(of: model.data, in: root.audioRoot.gameControllable) {
                Logger.networking.debug("PlayerController: SharePlay file-load-failure for \(model.data.id, privacy: .public) not reported, the file is already here")
                return
            }
            let failure = await response(for: model, isSuccess: false, requestData: false)
            await sendUpstream(model: failure)
            return
        }
        await receivedProcess(model, origin: .file)
    }
}
