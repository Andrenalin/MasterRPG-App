// @copyright André Trettin

import CoreRPG
import Foundation
import os.log
import PdfRPG

private enum PlayerPdfRevealValidation: Sendable {
    case valid
    case awaitingAuthoritativeList
    case mismatch
}

extension PlayerController {
    func handlePdf(
        _ model: GameNetworkModel,
        locallyMirroredProxyPresentation: Bool = false
    ) async throws -> GameNetworkModel? {
        guard model.subType != .ok, model.subType != .failed else { return nil }

        let masterId = model.masterId
        if model.sender.isMaster,
           model.type == .reveal,
           model.subType == .show,
           model.targetId == nil {
            gameModel.removeDeferredPdfReveals(from: masterId)
        }
        if model.sender.isMaster,
           !(model.type == .update && model.subType == .pdfList) {
            let previousBaseline = root.pdfRoot.pdfGameControllable.masterVersion(
                for: model.data.id,
                masterId: masterId
            )
            if previousBaseline != nil, previousBaseline != model.data.effectiveAssetVersion {
                gameModel.removeRequestedPdfRepairId(model.data.id)
            }
            root.pdfRoot.pdfGameControllable.setMasterVersion(
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
            switch await playerPdfRevealValidation(for: model) {
            case .valid:
                validPlayerReveal = true
            case .awaitingAuthoritativeList:
                gameModel.deferPdfReveal(model)
                return nil
            case .mismatch:
                return nil
            }
        }

        guard model.sender.isMaster || model.type == .store || validPlayerReveal else { return nil }

        switch model.type {
        case .reveal:
            if try await root.pdfRoot.gameControllable.reveal(itemId: model.data.id, data: model.data, save: true) {
                gameModel.completePdfRepairAndSetUpdateType(model.data.id)
                let localPlayerId = root.gameModel.gameConfig.id
                root.pdfRoot.pdfGameControllable.markPdfAvailable(
                    itemId: model.data.id,
                    version: model.data.effectiveAssetVersion,
                    for: [localPlayerId, model.sender.id],
                    masterId: masterId
                )
                if model.data.data != nil, model.targetId == nil {
                    root.pdfRoot.pdfGameControllable.markPdfAvailableToCurrentPlayers(
                        itemId: model.data.id,
                        version: model.data.effectiveAssetVersion,
                        masterId: masterId
                    )
                }
                return await response(for: model, isSuccess: true, requestData: false)
            }

            let isFirstRequest = gameModel.insertRequestedPdfRepairId(model.data.id)
            guard isFirstRequest else { return nil }
            let baseline = root.pdfRoot.pdfGameControllable.masterVersion(
                for: model.data.id,
                masterId: masterId
            )
            var requestTrigger = model
            requestTrigger.type = .store
            requestTrigger.subType = .store
            return await response(
                for: requestTrigger,
                isSuccess: true,
                requestData: true,
                requestedVersion: baseline
            )
        case .store:
            try await root.pdfRoot.gameControllable.updateGame(
                data: model.data,
                hide: model.subType == .store,
                deep: true
            )
            let hasLocalData = await root.pdfRoot.gameControllable.hasLocalFileData(for: model.data.id)
            if hasLocalData {
                let completesReveal = gameModel.removeRequestedPdfRepairId(model.data.id)
                if completesReveal, await root.pdfRoot.gameControllable.setCurrent(itemId: model.data.id) {
                    gameModel.setGameUpdateType(.pdf)
                }
                let localPlayerId = root.gameModel.gameConfig.id
                root.pdfRoot.pdfGameControllable.markPdfAvailable(
                    itemId: model.data.id,
                    version: model.data.effectiveAssetVersion,
                    for: [localPlayerId],
                    masterId: masterId
                )
                return await response(for: model, isSuccess: true, requestData: false)
            }
            return nil
        case .update:
            guard model.subType == .pdfList else { return nil }
            guard await applyPdfList(model) else { return nil }
            await retryDeferredPdfReveals(from: model.masterId)
            return nil
        }
    }

    private func applyPdfList(_ model: GameNetworkModel) async -> Bool {
        guard model.sender.isMaster,
              gameModel.canApplyPdfList(from: model.masterId, counter: model.counter),
              await root.pdfRoot.pdfGameControllable.applyPdfList(
                  data: model.data,
                  for: model.masterId,
                  with: model.masterId,
                  authoritative: true
              )
        else { return false }

        gameModel.recordPdfList(counter: model.counter, from: model.masterId)
        return true
    }

    private func playerPdfRevealValidation(for model: GameNetworkModel) async -> PlayerPdfRevealValidation {
        if gameModel.asGameMaster {
            let senderIsAvailable = root.pdfRoot.pdfGameControllable.isPdfAvailable(
                itemId: model.data.id,
                for: model.sender.id,
                masterId: model.masterId
            )
            let baseline = root.pdfRoot.pdfGameControllable.masterVersion(
                for: model.data.id,
                masterId: model.masterId
            )
            return senderIsAvailable && baseline == model.data.effectiveAssetVersion ? .valid : .mismatch
        }

        guard gameModel.hasAuthoritativePdfList(from: model.masterId) else {
            return .awaitingAuthoritativeList
        }
        guard let senderVersion = root.pdfRoot.pdfGameControllable.reportedVersion(
            for: model.data.id,
            playerId: model.sender.id
        ) else {
            return .awaitingAuthoritativeList
        }
        guard senderVersion == model.data.effectiveAssetVersion else {
            return .mismatch
        }
        guard let baseline = root.pdfRoot.pdfGameControllable.masterVersion(
            for: model.data.id,
            masterId: model.masterId
        ) else {
            return .awaitingAuthoritativeList
        }
        return senderVersion == baseline ? .valid : .mismatch
    }

    private func retryDeferredPdfReveals(from masterId: UUID) async {
        let deferred = gameModel.deferredPdfReveals(from: masterId)
        for model in deferred {
            switch await playerPdfRevealValidation(for: model) {
            case .awaitingAuthoritativeList:
                continue
            case .mismatch:
                gameModel.removeDeferredPdfReveal(model)
            case .valid:
                gameModel.removeDeferredPdfReveal(model)
                guard await deferredPresentationIsCurrent(model) else { continue }
                do {
                    if let response = try await handlePdf(model) {
                        await sendUpstream(model: response)
                    }
                } catch {
                    // Item was already removed from the deferred queue above
                    // — ask the master to resend instead of only logging.
                    // See CODE_AUDIT_Network §5.23.
                    Logger.networking.error("PlayerController: Deferred PDF reveal failed: \(error.logIdentifier, privacy: .public) \(error.localizedDescription, privacy: .private)")
                    let request = await response(for: model, isSuccess: true, requestData: true)
                    await sendUpstream(model: request)
                }
            }
        }
    }

    func sendPdfList() async {
        // A proxy mirrors its host and must not become an availability-report
        // participant of its own.
        guard root.gameModel.gameType != .proxy else { return }
        let pdfList = await root.pdfRoot.pdfGameControllable.pdfList(
            allPlayers: false,
            with: root.gameModel.gameConfig.master.id
        )
        await send(type: .update, subType: .pdfList, updated: pdfList, useJournal: false)
    }
}
