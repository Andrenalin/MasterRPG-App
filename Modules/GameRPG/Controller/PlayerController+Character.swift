// @copyright André Trettin

import CharacterRPG
import CoreRPG
import Foundation
import os.log

// Split out of PlayerController+Value.swift — this is outbound Character
// lifecycle (announcing/sending this player's own Character), not `.value`
// message handling. See CODE_AUDIT_Game §9.24.

extension PlayerController {
    func scheduleSendCharacter() async {
        scheduleSendCharacterTask()
    }

    /// The whole task-scheduling block (nil-check, id mint, task assignment)
    /// needs to stay one @MainActor unit so a concurrent caller can't observe
    /// a half-scheduled task. See CODE_AUDIT §3.1.
    private func scheduleSendCharacterTask() {
        guard gameModel.sendCharacterTask == nil else { return }
        let taskId = UUID()
        gameModel.sendCharacterTaskId = taskId
        gameModel.sendCharacterTask = Task { [weak self] in
            // Companions edited while a send runs make it announce an old list; it then leaves
            // `hasSendPlayer` open and this runs it again. See CODE_AUDIT_24 §5.5.
            while let self {
                let generation = self.gameModel.companionGeneration
                await self.sendCharacter()
                guard !Task.isCancelled, generation != self.gameModel.companionGeneration else { break }
            }
            self?.clearSendCharacterTask(if: taskId)
        }
    }

    private func clearSendCharacterTask(if taskId: UUID) {
        guard gameModel.sendCharacterTaskId == taskId else { return }
        gameModel.sendCharacterTask = nil
        gameModel.sendCharacterTaskId = nil
    }

    func sendCharacter() async {
        let gameType = root.gameModel.gameType
        let canSend = gameModel.canSendCharacter
        // A proxy device never announces a character: it mirrors the host
        // player and receives the host's character on readyProxy instead.
        guard canSend, gameType != .observer, gameType != .proxy else { return }
        let characterId = root.gameModel.gamePlayer.characterId
        let generation = gameModel.companionGeneration

        do {
            try Task.checkCancellation()
            var isOwnAnnounced = true
            // A player without a Character still brings its companions along.
            if let characterId {
                let reference = await root.characterRoot.gameControllable.share(id: characterId)
                try Task.checkCancellation()
                // A version the master already rejected several times is not announced again;
                // the companions are. See CODE_AUDIT_21 §5.5.
                if gameModel.mayAnnounceCharacter(version: reference.version) {
                    await announce(reference)
                } else {
                    isOwnAnnounced = false
                }
            }
            try await sendCompanionReferences()
            let lostMaster = gameModel.lostMaster
            guard !Task.isCancelled, !lostMaster, isOwnAnnounced else { return }
            // Companions that changed meanwhile were not part of this announcement.
            gameModel.reset(sendPlayer: generation == gameModel.companionGeneration)
        } catch is CancellationError {
            return
        } catch {
            // characterId can identify a specific player's Character — private. See CODE_AUDIT_Game §6.3.
            Logger.networking.error("PlayerController: Failed to send character \(characterId?.uuidString ?? "none", privacy: .private): \(error.logIdentifier, privacy: .public) \(error.localizedDescription, privacy: .private)")
        }
    }

    /// The companions changed: announce the Character and the companions again. Every message
    /// carries the companion list, so the Character's announcement also tells the master about
    /// a removed companion.
    func announceCompanions() async {
        gameModel.noteCompanionsChanged()
        gameModel.reset(sendPlayer: false)
        await scheduleSendCharacter()
    }

    /// Advertises each enabled companion like the Character: id and version only, the master
    /// asks for the package when its copy differs (see `handleValue`).
    private func sendCompanionReferences() async throws {
        for companion in root.gameModel.gamePlayer.companions where companion.isEnabled {
            try Task.checkCancellation()
            guard root.characterRoot.valueGameControllable.playerPinName(for: companion.characterId) != nil else { continue }
            let reference = await root.characterRoot.gameControllable.share(id: companion.characterId)
            try Task.checkCancellation()
            await announce(reference)
        }
    }

    /// First advertises only the Character id and its deterministic version. The master requests
    /// the full package only when its local version differs. Value messages never use the
    /// SharePlay Journal.
    private func announce(_ reference: NetworkCodableDataType) async {
        await send(
            type: .update,
            subType: .store,
            updated: reference,
            relayToProxyClients: false
        )
    }
}
