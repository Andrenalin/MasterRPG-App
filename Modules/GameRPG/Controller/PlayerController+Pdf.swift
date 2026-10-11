// @copyright André Trettin

import CoreRPG
import Foundation
import os.log
import PdfRPG

extension PlayerController {
    func handlePdf(_ model: GameNetworkModel) async throws -> GameNetworkModel? {
        // PDFs come from the game master only; a player shows one through the master.
        guard !model.isAcknowledgement, model.sender.isMaster else { return nil }

        let masterId = model.masterId
        let localPlayerId = root.gameModel.gameConfig.id
        let pdf = root.pdfRoot.pdfGameControllable
        if !(model.type == .update && model.subType == .pdfList) {
            pdf.setMasterVersion(
                itemId: model.data.id,
                version: model.data.effectiveAssetVersion,
                masterId: masterId
            )
        }

        switch model.type {
        case .reveal:
            guard try await root.pdfRoot.gameControllable.reveal(itemId: model.data.id, data: model.data, save: true) else {
                return await response(for: model, isSuccess: true, requestData: true)
            }
            gameModel.setGameUpdateType(.pdf)
            pdf.markPdfAvailable(
                itemId: model.data.id,
                version: model.data.effectiveAssetVersion,
                for: [localPlayerId, masterId],
                masterId: masterId
            )
            return await response(for: model, isSuccess: true, requestData: false)
        case .store:
            if model.data.data != nil {
                try await root.pdfRoot.gameControllable.updateGame(
                    data: model.data,
                    hide: model.subType == .store,
                    deep: true
                )
            }
            guard await holdsFile(of: model.data, in: root.pdfRoot.gameControllable) else {
                return await response(for: model, isSuccess: true, requestData: true)
            }
            pdf.markPdfAvailable(
                itemId: model.data.id,
                version: model.data.effectiveAssetVersion,
                for: [localPlayerId],
                masterId: masterId
            )
            return await response(for: model, isSuccess: true, requestData: false)
        case .update:
            guard model.subType == .pdfList else { return nil }
            _ = await applyPdfList(model)
            return nil
        }
    }

    private func applyPdfList(_ model: GameNetworkModel) async -> Bool {
        guard gameModel.canApplyPdfList(from: model.masterId, counter: model.counter),
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

    func sendPdfList() async {
        // A proxy is a private mirror of its host and must not become a separate
        // availability-report participant.
        guard root.gameModel.gameType != .proxy else { return }
        let pdfList = await root.pdfRoot.pdfGameControllable.pdfList(
            allPlayers: false,
            with: root.gameModel.gameConfig.master.id
        )
        await send(type: .update, subType: .pdfList, updated: pdfList)
    }
}
