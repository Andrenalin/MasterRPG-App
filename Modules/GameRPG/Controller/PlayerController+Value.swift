// @copyright André Trettin

import CharacterRPG
import CoreRPG
import Foundation
import os.log

extension PlayerController {
    func handleValue(_ model: GameNetworkModel) async throws -> GameNetworkModel? {
        guard await root.gameModel.gameType != .proxy else { return try await handleProxyValue(model) }
        // A normal player accepts only the master's targeted response to the
        // join announcement. No Value reveal, result, loot, or live update is
        // processed during the game.
        guard model.sender.isMaster,
              model.type == .update,
              model.subType == .store,
              model.data.data == nil,
              let characterId = await root.gameModel.gamePlayer.characterId,
              characterId == model.data.id
        else { return nil }

        try Task.checkCancellation()
        let package = try await root.characterRoot.gameControllable.createGameData(for: characterId)
        try Task.checkCancellation()
        // Character packages can be large, but only the game master consumes
        // them. Keep them off the SharePlay Journal and away from local proxy
        // clients; SharePlay peers may see the Messenger message and ignore it.
        await send(
            type: .update,
            subType: .store,
            updated: package,
            useJournal: false,
            relayToProxyClients: false
        )
        return nil
    }
}

// MARK: - Send Character

extension PlayerController {
    func scheduleSendCharacter() async {
        await scheduleSendCharacterTask()
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
        let gameType = await root.gameModel.gameType
        let canSend = await gameModel.canSendCharacter
        // A proxy device never announces a character: it mirrors the host
        // player and receives the host's character on readyProxy instead.
        guard canSend, gameType != .observer, gameType != .proxy,
              let characterId = await root.gameModel.gamePlayer.characterId
        else { return }

        do {
            try Task.checkCancellation()
            let reference = await root.characterRoot.gameControllable.share(id: characterId)
            try Task.checkCancellation()
            // First advertise only the Character ID and deterministic version.
            // The master requests the full package only when its local version
            // differs. Value messages never use the SharePlay Journal.
            await send(
                type: .update,
                subType: .store,
                updated: reference,
                useJournal: false,
                relayToProxyClients: false
            )
            let lostMaster = await gameModel.lostMaster
            guard !Task.isCancelled, !lostMaster else { return }
            await gameModel.reset(sendPlayer: true)
        } catch is CancellationError {
            return
        } catch {
            Logger.networking.error("PlayerController: Failed to send character \(characterId, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}
