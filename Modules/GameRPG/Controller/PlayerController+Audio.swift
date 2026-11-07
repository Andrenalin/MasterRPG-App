// @copyright André Trettin

import CoreRPG
import Foundation
import os.log
import AudioRPG

extension PlayerController {
    func handleAudio(
        _ model: GameNetworkModel,
        usesSharePlayPlaybackCoordination: Bool = false
    ) async throws -> GameNetworkModel? {
        if model.subType == .ok {
            root.audioRoot.gameControllable.report(itemId: model.data.id, for: model.sender.id)
            return nil
        }
        // Audio comes from the game master only; a player shares one through the master.
        guard model.subType != .failed, model.sender.isMaster else { return nil }

        switch model.type {
        case .reveal:
            let revealed = try await root.audioRoot.gameControllable.reveal(itemId: model.data.id, data: model.data, save: true)
            guard revealed, await root.audioRoot.audioGameControllable.hasLocalFileData(for: model.data.id) else {
                return await response(for: model, isSuccess: true, requestData: true)
            }
            return await acceptAudio(model)
        case .store:
            // A store keeps the audio without showing it: the game master sends one to every
            // player before it starts an audio that somebody lacks.
            if model.data.data != nil {
                try await root.audioRoot.gameControllable.updateGame(data: model.data, hide: model.subType == .store, deep: true)
            }
            guard await holdsFile(of: model.data, in: root.audioRoot.gameControllable) else {
                return await response(for: model, isSuccess: true, requestData: true)
            }
            return await acceptAudio(model)
        case .update:
            switch model.subType {
            case .audioList:
                // On the game master's own device the master controller is authoritative: this
                // snapshot could land after newer acknowledgements and erase them. See
                // CODE_AUDIT_Audio2 §5.8.
                guard !gameModel.asGameMaster else { return nil }
                _ = applyAudioList(model)
            case .playAudio:
                if root.audioRoot.audioGameControllable.shouldPlay(with: model.data) {
                    reportAudioAvailableToCurrentPlayers(itemId: model.data.id, model: model)
                }
                let asGameMaster = gameModel.asGameMaster
                if Self.shouldStartAudioPlayback(
                    isSharePlayActive: usesSharePlayPlaybackCoordination,
                    asGameMaster: asGameMaster
                ) {
                    // A failed playlist load/playback start used to be
                    // silently swallowed here. See CODE_AUDIT_Game §4.2.
                    do {
                        try await root.audioRoot.audioGameControllable.play(with: model.data)
                    } catch {
                        Logger.networking.error("PlayerController: Failed to start audio playback for \(model.data.id, privacy: .public): \(error.logIdentifier, privacy: .public) \(error.localizedDescription, privacy: .private)")
                    }
                } else {
                    // The master device initiates playback; other SharePlay
                    // participants only prepare for AVPlayerPlaybackCoordinator.
                    await root.audioRoot.audioGameControllable.loadPlaylist(with: model.data)
                }
            default:
                break
            }
        }
        return nil
    }

    /// The audio is readable here: the master learns it, and a track that belongs to the
    /// playlist that plays here joins it.
    private func acceptAudio(_ model: GameNetworkModel) async -> GameNetworkModel {
        root.audioRoot.audioGameControllable.applyAudio(id: model.data.id, for: [root.gameModel.gameConfig.id, model.sender.id])
        await root.audioRoot.audioGameControllable.itemArrived(id: model.data.id)
        return await response(for: model, isSuccess: true, requestData: false)
    }

    private func applyAudioList(_ model: GameNetworkModel) -> Bool {
        guard model.sender.isMaster,
              gameModel.canApplyList(.audio, from: model.masterId, counter: model.counter),
              root.audioRoot.audioGameControllable.applyAudioList(
                  data: model.data,
                  for: model.masterId,
                  authoritative: true
              )
        else { return false }

        gameModel.recordList(.audio, counter: model.counter, from: model.masterId)
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
        guard root.gameModel.gameType != .proxy else { return }
        let audioList = await root.audioRoot.audioGameControllable.audioList(allPlayers: false, with: root.gameModel.gameConfig.id)
        await send(type: .update, subType: .audioList, updated: audioList)
    }
}
