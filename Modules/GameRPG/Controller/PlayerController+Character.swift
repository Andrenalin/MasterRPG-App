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
            await self?.sendCharacter()
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
        guard canSend, gameType != .observer, gameType != .proxy,
              let characterId = root.gameModel.gamePlayer.characterId
        else { return }

        do {
            try Task.checkCancellation()
            let reference = await root.characterRoot.gameControllable.share(id: characterId)
            try Task.checkCancellation()
            // A version the master already rejected several times is not announced again.
            // See CODE_AUDIT_21 §5.5.
            guard gameModel.mayAnnounceCharacter(version: reference.version) else { return }
            // First advertise only the Character ID and deterministic version.
            // The master requests the full package only when its local version
            // differs. Value messages never use the SharePlay Journal.
            await send(
                type: .update,
                subType: .store,
                updated: reference,
                relayToProxyClients: false
            )
            let lostMaster = gameModel.lostMaster
            guard !Task.isCancelled, !lostMaster else { return }
            gameModel.reset(sendPlayer: true)
        } catch is CancellationError {
            return
        } catch {
            // characterId can identify a specific player's Character — private. See CODE_AUDIT_Game §6.3.
            Logger.networking.error("PlayerController: Failed to send character \(characterId, privacy: .private): \(error.logIdentifier, privacy: .public) \(error.localizedDescription, privacy: .private)")
        }
    }
}
