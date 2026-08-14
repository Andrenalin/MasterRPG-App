// @copyright André Trettin

import CoreRPG
import Foundation
import os.log
import SpaceRPG

private enum PlayerSpaceRevealValidation: Sendable {
    case valid
    case awaitingAuthoritativeList
    case mismatch
}

private enum PlayerSpaceTransformValidation: Sendable {
    case valid
    case awaitingAuthoritativeList
    case mismatch
}

extension PlayerController {
    func handleSpace(
        _ model: GameNetworkModel,
        locallyMirroredProxyPresentation: Bool = false
    ) async throws -> GameNetworkModel? {
        guard model.subType != .ok, model.subType != .failed else { return nil }

        let masterId = model.masterId
        if model.sender.isMaster,
           model.type == .reveal,
           model.subType == .show,
           model.targetId == nil {
            await gameModel.removeDeferredSpaceReveals(from: masterId)
        }
        if model.sender.isMaster,
           !(model.type == .update && (model.subType == .spaceList || model.subType == .spaceTransform)) {
            let previousBaseline = await root.spaceRoot.spaceGameControllable.masterVersion(
                for: model.data.id,
                masterId: masterId
            )
            if previousBaseline != nil, previousBaseline != model.data.effectiveAssetVersion {
                await gameModel.removeRequestedSpaceRepairId(model.data.id)
            }
            await root.spaceRoot.spaceGameControllable.setMasterVersion(
                itemId: model.data.id,
                version: model.data.effectiveAssetVersion,
                masterId: masterId
            )
        }

        let validPlayerReveal: Bool
        if locallyMirroredProxyPresentation, model.isPlayerFilePresentationEvent {
            validPlayerReveal = true
        } else if model.sender.isMaster || !model.isPlayerFilePresentationEvent {
            validPlayerReveal = false
        } else {
            switch await playerSpaceRevealValidation(for: model) {
            case .valid:
                validPlayerReveal = true
            case .awaitingAuthoritativeList:
                await gameModel.deferSpaceReveal(model)
                return nil
            case .mismatch:
                return nil
            }
        }

        let isPlayerSpaceTransform = model.sender.role == .player &&
            model.type == .update &&
            model.subType == .spaceTransform &&
            model.data.type == .space &&
            model.effectiveAudience == .group

        guard model.sender.isMaster || model.type == .store || validPlayerReveal || isPlayerSpaceTransform else {
            return nil
        }

        switch model.type {
        case .reveal:
            if try await root.spaceRoot.gameControllable.reveal(itemId: model.data.id, data: model.data, save: true) {
                // Switching the presentation mode: the modeChanged observer
                // reconfigures the spatial template, and the game screen opens
                // the immersive space when it shows the space module.
                await completeSpaceReveal(itemId: model.data.id)
                let localPlayerId = await root.gameModel.gameConfig.id
                await root.spaceRoot.spaceGameControllable.markSpaceAvailable(
                    itemId: model.data.id,
                    version: model.data.effectiveAssetVersion,
                    for: [localPlayerId, model.sender.id],
                    masterId: masterId
                )
                if model.data.data != nil, model.targetId == nil {
                    await root.spaceRoot.spaceGameControllable.markSpaceAvailableToCurrentPlayers(
                        itemId: model.data.id,
                        version: model.data.effectiveAssetVersion,
                        masterId: masterId
                    )
                }
                return await response(for: model, isSuccess: true, requestData: false)
            } else {
                let isFirstRequest = await gameModel.insertRequestedSpaceRepairId(model.data.id)
                guard isFirstRequest else { return nil }
                let baseline = await root.spaceRoot.spaceGameControllable.masterVersion(
                    for: model.data.id,
                    masterId: masterId
                )
                return await response(
                    for: model,
                    isSuccess: true,
                    requestData: true,
                    requestedVersion: baseline
                )
            }
        case .store:
            try await root.spaceRoot.gameControllable.updateGame(data: model.data, hide: model.subType == .store, deep: true)
            let hasLocalData = await root.spaceRoot.gameControllable.hasLocalFileData(for: model.data.id)
            if hasLocalData {
                let completesReveal = await gameModel.removeRequestedSpaceRepairId(model.data.id)
                if completesReveal,
                   await root.spaceRoot.gameControllable.setCurrent(itemId: model.data.id) {
                    await completeSpaceReveal(itemId: model.data.id)
                }
                let localPlayerId = await root.gameModel.gameConfig.id
                await root.spaceRoot.spaceGameControllable.markSpaceAvailable(
                    itemId: model.data.id,
                    version: model.data.effectiveAssetVersion,
                    for: [localPlayerId],
                    masterId: masterId
                )
                return await response(for: model, isSuccess: true, requestData: false)
            }
            let isFirstRequest = await gameModel.insertRequestedSpaceRepairId(model.data.id)
            guard isFirstRequest else { return nil }
            return await response(for: model, isSuccess: true, requestData: true)
        case .update:
            switch model.subType {
            case .spaceList:
                guard await applySpaceList(model) else { return nil }
                await retryDeferredSpaceReveals(from: model.masterId)
                await retryDeferredSpaceTransforms(from: model.masterId)
                return nil
            case .spaceTransform:
                let baseline = await root.spaceRoot.spaceGameControllable.masterVersion(
                    for: model.data.id,
                    masterId: model.masterId
                )
                guard baseline == nil || baseline == model.data.effectiveAssetVersion else { return nil }
                if !model.sender.isMaster {
                    switch await playerSpaceTransformValidation(for: model) {
                    case .valid:
                        break
                    case .awaitingAuthoritativeList:
                        await gameModel.deferSpaceTransform(model)
                        return nil
                    case .mismatch:
                        return nil
                    }
                }
                _ = await root.spaceRoot.spaceGameControllable.applySpaceTransform(
                    data: model.data,
                    counter: model.counter,
                    timestamp: model.timestamp
                )
                return nil
            default:
                break
            }
            if await root.spaceRoot.gameControllable.setCurrent(itemId: model.data.id) {
                await gameModel.setGameUpdateType(.space)
            }
        }
        return nil
    }

    private func applySpaceList(_ model: GameNetworkModel) async -> Bool {
        guard model.sender.isMaster,
              gameModel.canApplySpaceList(from: model.masterId, counter: model.counter),
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

    private func playerSpaceRevealValidation(for model: GameNetworkModel) async -> PlayerSpaceRevealValidation {
        if await gameModel.asGameMaster {
            let senderIsAvailable = await root.spaceRoot.spaceGameControllable.isSpaceAvailable(
                itemId: model.data.id,
                for: model.sender.id,
                masterId: model.masterId
            )
            let baseline = await root.spaceRoot.spaceGameControllable.masterVersion(
                for: model.data.id,
                masterId: model.masterId
            )
            return senderIsAvailable && baseline == model.data.effectiveAssetVersion ? .valid : .mismatch
        }

        guard await gameModel.hasAuthoritativeSpaceList(from: model.masterId) else {
            return .awaitingAuthoritativeList
        }
        guard let senderVersion = await root.spaceRoot.spaceGameControllable.reportedVersion(
            for: model.data.id,
            playerId: model.sender.id
        ) else {
            return .awaitingAuthoritativeList
        }
        guard senderVersion == model.data.effectiveAssetVersion else {
            return .mismatch
        }
        guard let baseline = await root.spaceRoot.spaceGameControllable.masterVersion(
            for: model.data.id,
            masterId: model.masterId
        ) else {
            return .awaitingAuthoritativeList
        }
        return senderVersion == baseline ? .valid : .mismatch
    }

    private func retryDeferredSpaceReveals(from masterId: UUID) async {
        let deferred = await gameModel.deferredSpaceReveals(from: masterId)
        for model in deferred {
            switch await playerSpaceRevealValidation(for: model) {
            case .awaitingAuthoritativeList:
                continue
            case .mismatch:
                await gameModel.removeDeferredSpaceReveal(model)
            case .valid:
                await gameModel.removeDeferredSpaceReveal(model)
                guard await deferredPresentationIsCurrent(model) else { continue }
                do {
                    if let response = try await handleSpace(model) {
                        await sendUpstream(model: response)
                    }
                } catch {
                    // The list itself is valid. A bad deferred file must not make
                    // availability sequencing fail or reserve a later counter.
                    Logger.networking.error("PlayerController: Deferred Space reveal failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    private func playerSpaceTransformValidation(
        for model: GameNetworkModel
    ) async -> PlayerSpaceTransformValidation {
        guard await root.gameModel.gameControl.features.spaceSharing else {
            return .mismatch
        }
        if await !gameModel.asGameMaster,
           await !gameModel.hasAuthoritativeSpaceList(from: model.masterId) {
            return .awaitingAuthoritativeList
        }
        guard let baseline = await root.spaceRoot.spaceGameControllable.masterVersion(
            for: model.data.id,
            masterId: model.masterId
        ) else {
            return .awaitingAuthoritativeList
        }
        guard baseline == model.data.effectiveAssetVersion else {
            return .mismatch
        }
        guard let senderVersion = await root.spaceRoot.spaceGameControllable.reportedVersion(
            for: model.data.id,
            playerId: model.sender.id
        ) else {
            return .awaitingAuthoritativeList
        }
        return senderVersion == baseline ? .valid : .mismatch
    }

    private func retryDeferredSpaceTransforms(from masterId: UUID) async {
        let deferred = await gameModel.deferredSpaceTransforms(from: masterId)
        for model in deferred {
            switch await playerSpaceTransformValidation(for: model) {
            case .awaitingAuthoritativeList:
                continue
            case .mismatch:
                await gameModel.removeDeferredSpaceTransform(model)
            case .valid:
                await gameModel.removeDeferredSpaceTransform(model)
                _ = await root.spaceRoot.spaceGameControllable.applySpaceTransform(
                    data: model.data,
                    counter: model.counter,
                    timestamp: model.timestamp
                )
            }
        }
    }

    func sendSpaceList() async {
        // A proxy mirrors its host and must not appear as a separate participant
        // in the Space availability/version matrix.
        guard await root.gameModel.gameType != .proxy else { return }
        let spaceList = await root.spaceRoot.spaceGameControllable.spaceList(
            allPlayers: false,
            with: root.gameModel.gameConfig.master.id
        )
        await send(type: .update, subType: .spaceList, updated: spaceList, useJournal: false)
    }
}
