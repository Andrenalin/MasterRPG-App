// @copyright André Trettin

import AudioRPG
import CoreRPG
import Foundation
import os.log

extension PlayerController {
    func handleAudio(
        _ model: GameNetworkModel,
        usesSharePlayPlaybackCoordination: Bool = false
    ) async throws -> GameNetworkModel? {
        if model.subType == .ok {
            await root.audioRoot.gameControllable.report(itemId: model.data.id, for: model.sender.id)
            return nil
        }
        guard model.subType != .failed else { return nil }

        switch model.type {
        case .reveal:
            let revealed = try await root.audioRoot.gameControllable.reveal(itemId: model.data.id, data: model.data, save: true)
            if revealed, await root.audioRoot.audioGameControllable.hasLocalAudioData(for: model.data.id) {
                await gameModel.removePendingAudioRequest(model.data.id)
                await root.audioRoot.audioGameControllable.applyAudio(id: model.data.id, for: [root.gameModel.gameConfig.id, model.sender.id])
                return await response(for: model, isSuccess: true, requestData: false)
            } else {
                await gameModel.insertPendingAudioRequest(model.data.id)
                return await response(for: model, isSuccess: true, requestData: true)
            }
        case .store:
            try await root.audioRoot.gameControllable.updateGame(data: model.data, hide: model.subType == .store, deep: true)
            guard await root.audioRoot.audioGameControllable.hasLocalAudioData(for: model.data.id) else {
                await gameModel.insertPendingAudioRequest(model.data.id)
                return await response(for: model, isSuccess: true, requestData: true)
            }
            let completesReveal = await gameModel.removePendingAudioRequest(model.data.id)
            if completesReveal {
                _ = await root.audioRoot.gameControllable.setCurrent(itemId: model.data.id)
            }
            await root.audioRoot.audioGameControllable.applyAudio(id: model.data.id, for: [root.gameModel.gameConfig.id, model.sender.id])
            return await response(for: model, isSuccess: true, requestData: false)
        case .update:
            switch model.subType {
            case .audioList:
                _ = await applyAudioList(model)
            case .playAudio:
                guard model.sender.isMaster else { return nil }
                if await root.audioRoot.audioGameControllable.shouldPlay(with: model.data) {
                    await reportAudioAvailableToCurrentPlayers(itemId: model.data.id, model: model)
                }
                let asGameMaster = await gameModel.asGameMaster
                if Self.shouldStartAudioPlayback(
                    isSharePlayActive: usesSharePlayPlaybackCoordination,
                    asGameMaster: asGameMaster
                ) {
                    let _ = await root.audioRoot.audioGameControllable.play(with: model.data).result
                } else {
                    // The master device initiates playback; other SharePlay
                    // participants only prepare for AVPlayerPlaybackCoordinator.
                    await root.audioRoot.audioGameControllable.loadPlaylist(id: model.data.id)
                }
            default:
                break
            }
        }
        return nil
    }

    private func applyAudioList(_ model: GameNetworkModel) -> Bool {
        guard model.sender.isMaster,
              gameModel.canApplyAudioList(from: model.masterId, counter: model.counter),
              root.audioRoot.audioGameControllable.applyAudioList(
                  data: model.data,
                  for: model.masterId,
                  authoritative: true
              )
        else { return false }

        gameModel.recordAudioList(counter: model.counter, from: model.masterId)
        return true
    }

    private func reportAudioAvailableToCurrentPlayers(itemId: UUID, model: GameNetworkModel) {
        var playerIds = Set(root.audioRoot.gameControllable.gameModel.currentPlayers)
        if playerIds.isEmpty {
            playerIds.formUnion(model.masterState?.controls.compactMap { $0.show ? $0.id : nil } ?? [])
        }
        playerIds.insert(model.masterId)
        for playerId in playerIds {
            root.audioRoot.gameControllable.report(itemId: itemId, for: playerId)
        }
    }

    func sendAudioList() async {
        // A proxy device stays invisible: the host answers for its audio
        // availability, and the host consumes any list that still arrives.
        guard await root.gameModel.gameType != .proxy else { return }
        let audioList = await root.audioRoot.audioGameControllable.audioList(allPlayers: false, with: root.gameModel.gameConfig.id)
        await send(type: .update, subType: .audioList, updated: audioList, useJournal: false)
    }
}
