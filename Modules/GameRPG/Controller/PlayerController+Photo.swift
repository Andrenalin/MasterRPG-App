// @copyright André Trettin

import CoreRPG
import Foundation
import os.log
import PhotoRPG

private enum PlayerPhotoRevealValidation: Sendable {
    case valid
    case awaitingAuthoritativeList
    case mismatch
}

extension PlayerController {
    func handlePhoto(
        _ model: GameNetworkModel,
        locallyMirroredProxyPresentation: Bool = false
    ) async throws -> GameNetworkModel? {
        guard model.subType != .ok, model.subType != .failed else { return nil }

        let masterId = model.masterId
        if model.sender.isMaster,
           model.type == .reveal,
           model.subType == .show,
           model.targetId == nil {
            // A canonical master presentation supersedes any peer reveal that
            // was waiting for availability evidence from this master.
            gameModel.removeDeferredPhotoReveals(from: masterId)
        }
        if model.sender.isMaster,
           !(model.type == .update && model.subType == .photoList) {
            root.photoRoot.photoGameControllable.setMasterVersion(
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
            switch await playerPhotoRevealValidation(for: model) {
            case .valid:
                validPlayerReveal = true
            case .awaitingAuthoritativeList:
                gameModel.deferPhotoReveal(model)
                return nil
            case .mismatch:
                return nil
            }
        }

        guard model.sender.isMaster || model.type == .store || validPlayerReveal else { return nil }

        switch model.type {
        case .reveal:
            if try await root.photoRoot.gameControllable.reveal(itemId: model.data.id, data: model.data, save: true) {
                presentPhoto(itemId: model.data.id)

                let localPlayerId = root.gameModel.gameConfig.id
                root.photoRoot.photoGameControllable.markPhotoAvailable(
                    itemId: model.data.id,
                    version: model.data.effectiveAssetVersion,
                    for: [localPlayerId, model.sender.id],
                    masterId: masterId
                )
                if model.data.data != nil, model.targetId == nil {
                    root.photoRoot.photoGameControllable.markPhotoAvailableToCurrentPlayers(
                        itemId: model.data.id,
                        version: model.data.effectiveAssetVersion,
                        masterId: masterId
                    )
                }
                return await response(for: model, isSuccess: true, requestData: false)
            } else {
                let baseline = root.photoRoot.photoGameControllable.masterVersion(
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
            try await root.photoRoot.gameControllable.updateGame(data: model.data, hide: model.subType == .store, deep: true)
            let hasLocalData = await root.photoRoot.gameControllable.hasLocalFileData(for: model.data.id)
            if hasLocalData {
                gameModel.removeRequestedRepairId(model.data.id)
                let localPlayerId = root.gameModel.gameConfig.id
                root.photoRoot.photoGameControllable.markPhotoAvailable(
                    itemId: model.data.id,
                    version: model.data.effectiveAssetVersion,
                    for: [localPlayerId],
                    masterId: masterId
                )
            }
            return await response(for: model, isSuccess: hasLocalData, requestData: !hasLocalData)
        case .update:
            switch model.subType {
            case .photoList:
                guard await applyPhotoList(model) else { return nil }
                await retryDeferredPhotoReveals(from: model.masterId)
                return nil
            default:
                if model.data.data != nil {
                    try await root.photoRoot.gameControllable.updateGame(data: model.data, hide: model.subType == .store, deep: true)
                }
            }
            if await root.photoRoot.gameControllable.setCurrent(itemId: model.data.id) {
                presentPhoto(itemId: model.data.id)
            }
        }
        return nil
    }

    /// A show-photo event: switches the game screen to the photo and names it as the presented
    /// photo, which the visionOS 3D image viewer follows. A `.store` only caches its photo and
    /// never comes here.
    func presentPhoto(itemId: UUID) {
        gameModel.setGameUpdateType(.photo)
        root.photoRoot.photoGameControllable.presentPhoto(itemId: itemId)
    }

    private func applyPhotoList(_ model: GameNetworkModel) async -> Bool {
        guard model.sender.isMaster,
              gameModel.canApplyPhotoList(from: model.masterId, counter: model.counter),
              await root.photoRoot.photoGameControllable.applyPhotoList(
                  data: model.data,
                  for: model.masterId,
                  with: model.masterId,
                  authoritative: true
              )
        else { return false }

        gameModel.recordPhotoList(counter: model.counter, from: model.masterId)
        return true
    }

    private func playerPhotoRevealValidation(for model: GameNetworkModel) async -> PlayerPhotoRevealValidation {
        if gameModel.asGameMaster {
            let senderIsAvailable = root.photoRoot.photoGameControllable.isPhotoAvailable(
                itemId: model.data.id,
                for: model.sender.id,
                masterId: model.masterId
            )
            let baseline = root.photoRoot.photoGameControllable.masterVersion(
                for: model.data.id,
                masterId: model.masterId
            )
            return senderIsAvailable && baseline == model.data.effectiveAssetVersion ? .valid : .mismatch
        }

        guard gameModel.hasAuthoritativePhotoList(from: model.masterId) else {
            return .awaitingAuthoritativeList
        }

        guard let senderVersion = root.photoRoot.photoGameControllable.reportedVersion(
            for: model.data.id,
            playerId: model.sender.id
        ) else {
            // Another player's report may simply not have reached the master
            // when this authoritative snapshot was broadcast.
            return .awaitingAuthoritativeList
        }

        guard senderVersion == model.data.effectiveAssetVersion else {
            return .mismatch
        }
        guard let baseline = root.photoRoot.photoGameControllable.masterVersion(
            for: model.data.id,
            masterId: model.masterId
        ) else {
            return .awaitingAuthoritativeList
        }
        return senderVersion == baseline ? .valid : .mismatch
    }

    private func retryDeferredPhotoReveals(from masterId: UUID) async {
        let deferred = gameModel.deferredPhotoReveals(from: masterId)
        for model in deferred {
            switch await playerPhotoRevealValidation(for: model) {
            case .awaitingAuthoritativeList:
                continue
            case .mismatch:
                gameModel.removeDeferredPhotoReveal(model)
            case .valid:
                gameModel.removeDeferredPhotoReveal(model)
                guard await deferredPresentationIsCurrent(model) else { continue }
                do {
                    if let response = try await handlePhoto(model) {
                        await sendUpstream(model: response)
                    }
                } catch {
                    // The original network event was already accepted, and
                    // this item was already removed from the deferred queue
                    // above — a bad deferred payload must not make the
                    // photo-list update loop fail, but silently dropping it
                    // here left no ack and no way back. Ask the master to
                    // resend instead of only logging. See
                    // CODE_AUDIT_Network §5.23.
                    Logger.networking.error("PlayerController: Deferred photo reveal failed: \(error.logIdentifier, privacy: .public) \(error.localizedDescription, privacy: .private)")
                    let request = await response(for: model, isSuccess: true, requestData: true)
                    await sendUpstream(model: request)
                }
            }
        }
    }

    func sendPhotoList() async {
        // A proxy is a private mirror of its host and must not become a separate
        // availability-report participant.
        guard root.gameModel.gameType != .proxy else { return }
        let photoList = await root.photoRoot.photoGameControllable.photoList(
            allPlayers: false,
            with: root.gameModel.gameConfig.master.id
        )
        await send(type: .update, subType: .photoList, updated: photoList, useJournal: false)
    }
}
