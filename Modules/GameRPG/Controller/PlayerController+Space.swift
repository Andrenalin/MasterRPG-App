// @copyright André Trettin

import CoreRPG
import Foundation
import os.log
import SpaceRPG

extension PlayerController {
    func handleSpace(_ model: GameNetworkModel) async throws -> GameNetworkModel? {
        guard !model.isAcknowledgement else { return nil }

        if model.isPlayerGroupEvent {
            // Another player moved the Space.
            applySpaceTransform(model)
            return nil
        }

        // Spaces come from the game master only; a player shows one through the master.
        guard model.sender.isMaster else { return nil }

        let masterId = model.masterId
        let localPlayerId = root.gameModel.gameConfig.id
        let space = root.spaceRoot.spaceGameControllable
        if !(model.type == .update && (model.subType == .spaceList || model.subType == .spaceTransform)) {
            space.setMasterVersion(
                itemId: model.data.id,
                version: model.data.effectiveAssetVersion,
                masterId: masterId
            )
        }

        switch model.type {
        case .reveal:
            guard try await root.spaceRoot.gameControllable.reveal(itemId: model.data.id, data: model.data, save: true) else {
                return await response(for: model, isSuccess: true, requestData: true)
            }
            // The game screen opens the immersive space itself when it
            // shows the space module — see GameRootViewer's reveal
            // handler.
            gameModel.setGameUpdateType(.space)
            space.markSpaceAvailable(
                itemId: model.data.id,
                version: model.data.effectiveAssetVersion,
                for: [localPlayerId, masterId],
                masterId: masterId
            )
            return await response(for: model, isSuccess: true, requestData: false)
        case .store:
            if model.data.data != nil {
                try await root.spaceRoot.gameControllable.updateGame(data: model.data, hide: model.subType == .store, deep: true)
            }
            guard await holdsFile(of: model.data, in: root.spaceRoot.gameControllable) else {
                return await response(for: model, isSuccess: true, requestData: true)
            }
            space.markSpaceAvailable(
                itemId: model.data.id,
                version: model.data.effectiveAssetVersion,
                for: [localPlayerId],
                masterId: masterId
            )
            return await response(for: model, isSuccess: true, requestData: false)
        case .update:
            switch model.subType {
            case .spaceList:
                _ = await applySpaceList(model)
                return nil
            case .spaceTransform:
                applySpaceTransform(model)
                return nil
            default:
                break
            }
            if await root.spaceRoot.gameControllable.setCurrent(itemId: model.data.id) {
                gameModel.setGameUpdateType(.space)
            }
        }
        return nil
    }

    /// Applies a transform of the master's version of the Space. A player's transform also
    /// needs Space sharing to be on.
    private func applySpaceTransform(_ model: GameNetworkModel) {
        guard model.sender.isMaster || root.gameModel.gameControl.features.spaceSharing else { return }
        let baseline = root.spaceRoot.spaceGameControllable.masterVersion(
            for: model.data.id,
            masterId: model.masterId
        )
        guard baseline == nil || baseline == model.data.effectiveAssetVersion else { return }
        _ = root.spaceRoot.spaceGameControllable.applySpaceTransform(
            data: model.data,
            counter: model.counter,
            timestamp: model.timestamp
        )
    }

    private func applySpaceList(_ model: GameNetworkModel) async -> Bool {
        guard gameModel.canApplySpaceList(from: model.masterId, counter: model.counter),
              await root.spaceRoot.spaceGameControllable.applySpaceList(
                  data: model.data,
                  for: model.masterId,
                  with: model.masterId,
                  authoritative: true
              )
        else { return false }

        gameModel.recordSpaceList(counter: model.counter, from: model.masterId)
        return true
    }

    func sendSpaceList() async {
        // A proxy is a private mirror of its host and must not become a separate
        // availability-report participant.
        guard root.gameModel.gameType != .proxy else { return }
        let spaceList = await root.spaceRoot.spaceGameControllable.spaceList(
            allPlayers: false,
            with: root.gameModel.gameConfig.master.id
        )
        await send(type: .update, subType: .spaceList, updated: spaceList)
    }
}
