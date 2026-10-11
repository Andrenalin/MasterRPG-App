// @copyright André Trettin

import AdventureRPG
import CoreRPG
import DiceRPG
import Foundation
import os.log
import AudioRPG
import MapRPG
import PhotoRPG
import TableRPG
import CharacterRPG
import WeatherRPG
import PdfRPG
import SpaceRPG

// MARK: - Pdf Messages

extension MasterController {
    func handlePdf(_ model: GameNetworkModel) async throws -> NetworkCodableDataType? {
        if model.subType == .ok {
            await recordFileOkAck(
                model,
                controllable: root.pdfRoot.gameControllable,
                setMasterVersion: { root.pdfRoot.pdfGameControllable.setMasterVersion(itemId: $0, version: $1, masterId: $2) },
                markAvailable: { root.pdfRoot.pdfGameControllable.markPdfAvailable(itemId: $0, version: $1, for: $2, masterId: $3) },
                announceList: { await broadcastPdfList() }
            )
            return nil
        }
        guard model.subType != .failed else { return nil }

        if model.isAssetRequest {
            // An iCloud file that has not downloaded cannot be exported.
            guard await root.pdfRoot.gameControllable.hasLocalFileData(for: model.data.id) else { return nil }
            return try await root.pdfRoot.gameControllable.createGameData(for: model.data.id)
        }
        guard model.type == .update else { return nil }

        switch model.subType {
        case .pdfList:
            guard await applyPdfList(model) else { return nil }
            await broadcastPdfList()
        case .generic:
            guard model.sender.role == .player else { return nil }
            await showPlayerContribution(model, controllable: root.pdfRoot.gameControllable)
        default:
            break
        }
        return nil
    }

    /// Sends every player the authoritative report list: who has which version.
    private func broadcastPdfList() async {
        let list = await root.pdfRoot.pdfGameControllable.pdfList(
            allPlayers: true,
            with: root.gameModel.gameConfig.id
        )
        await send(type: .update, subtype: .pdfList, updated: list)
    }

    private func applyPdfList(_ model: GameNetworkModel) async -> Bool {
        await applyFileList(
            model,
            canApply: { gameModel.canApplyPdfList(from: $0, counter: $1) },
            apply: { data, senderId, masterId, authoritative in
                await root.pdfRoot.pdfGameControllable.applyPdfList(
                    data: data,
                    for: senderId,
                    with: masterId,
                    authoritative: authoritative
                )
            },
            record: { gameModel.recordPdfList(counter: $0, from: $1) }
        )
    }
}
