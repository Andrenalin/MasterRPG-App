// @copyright André Trettin

import CharacterRPG
import CoreRPG
import Foundation
import os.log

extension PlayerController: PlayerNetworkProxyControllerDelegate {
    func lostProxyConnection() async {
        Logger.networking.debug("PlayerController: Lost Proxy Connection - Reset State")
        await lostConnection()
    }

    func readyProxy() async {
        Logger.networking.debug("PlayerController: Proxy Ready")
        await gameModel.reset(lostMaster: false)
        await sendAudioList()
        await sendPhotoList()
        await sendPdfList()
        await sendSpaceList()
        await scheduleSendCharacter()
    }

    func receivedProxy(_ model: GameNetworkModel) async {
        Logger.networking.debug("PlayerController: Proxy Received \(model.counter, privacy: .public) / \(model.proxyCounter, privacy: .public): \(model.type.debugDescription, privacy: .public) - \(model.subType.debugDescription, privacy: .public), \(model.data.type.token, privacy: .public) id: \(model.data.id, privacy: .public)")
        await receivedProcess(model, fromProxy: true)
    }
}

// MARK: - Proxy Value

extension PlayerController {
    func handleProxyValue(_ model: GameNetworkModel) async throws -> GameNetworkModel? {
        // The one proxy-specific Value flow is the host Character bootstrap.
        // Ignore every other legacy Value action or metadata-only message.
        guard model.sender.isMaster,
              model.type == .update,
              model.subType == .store,
              model.data.data != nil
        else { return nil }

        try await root.characterRoot.gameControllable.updateGame(data: model.data, hide: false, deep: true)
        await scheduleProxyFocus(characterId: model.data.id)
        return nil
    }
}

// MARK: - Proxy Focus

extension PlayerController {
    func scheduleProxyFocus(characterId: UUID) async {
        await scheduleProxyFocusTask(characterId: characterId)
    }

    /// Same reasoning as `scheduleSendCharacterTask` — the cancel/mint/assign
    /// sequence must stay one @MainActor unit. See CODE_AUDIT §3.1.
    @MainActor
    private func scheduleProxyFocusTask(characterId: UUID) {
        gameModel.proxyFocusTask?.cancel()
        let taskId = UUID()
        gameModel.proxyFocusTaskId = taskId
        gameModel.proxyFocusTask = Task { [weak self] in
            guard let self else { return }
            _ = await root.characterRoot.gameControllable.setCurrent(itemId: characterId)
            await root.characterRoot.gameControllable.focus(on: characterId)
            do {
                try await Task.sleep(for: .seconds(1))
            } catch {
                clearProxyFocusTask(if: taskId)
                return
            }
            guard !Task.isCancelled else {
                clearProxyFocusTask(if: taskId)
                return
            }
            completeProxyFocus(characterId: characterId, if: taskId)
        }
    }

    @MainActor
    private func clearProxyFocusTask(if taskId: UUID) {
        guard gameModel.proxyFocusTaskId == taskId else { return }
        gameModel.proxyFocusTask = nil
        gameModel.proxyFocusTaskId = nil
    }

    @MainActor
    private func completeProxyFocus(characterId: UUID, if taskId: UUID) {
        guard gameModel.proxyFocusTaskId == taskId else { return }
        root.gameModel.selectedCharacter = characterId
        gameModel.proxyFocusTask = nil
        gameModel.proxyFocusTaskId = nil
    }
}
