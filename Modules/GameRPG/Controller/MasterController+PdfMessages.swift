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
                networkVersion: { await root.pdfRoot.gameControllable.networkVersion(for: $0) },
                setMasterVersion: { root.pdfRoot.pdfGameControllable.setMasterVersion(itemId: $0, version: $1, masterId: $2) },
                markAvailable: { root.pdfRoot.pdfGameControllable.markPdfAvailable(itemId: $0, version: $1, for: $2, masterId: $3) }
            )
            return nil
        }
        guard model.subType != .failed else { return nil }

        let masterId = root.gameModel.gameConfig.id
        if model.purpose == .assetRequest {
            guard model.type == .reveal || model.type == .store,
                  await root.pdfRoot.gameControllable.hasLocalFileData(for: model.data.id)
            else { return nil }
            return try await root.pdfRoot.gameControllable.createGameData(for: model.data.id)
        }

        switch model.type {
        case .reveal:
            let reference = await root.pdfRoot.gameControllable.share(id: model.data.id)
            root.pdfRoot.pdfGameControllable.setMasterVersion(
                itemId: reference.id,
                version: reference.effectiveAssetVersion,
                masterId: masterId
            )
            let senderIsAvailable = root.pdfRoot.pdfGameControllable.isPdfAvailable(
                itemId: model.data.id,
                for: model.sender.id,
                masterId: masterId
            )
            let matchesBaseline = model.data.effectiveAssetVersion == reference.effectiveAssetVersion

            if senderIsAvailable, matchesBaseline {
                if model.data.data != nil {
                    gameModel.markSentGameItem(
                        type: .pdf,
                        id: model.data.id,
                        version: reference.effectiveAssetVersion
                    )
                }
                // Remote transports already delivered the peer reveal. Only
                // the co-located player controller needs the relay.
                await root.networkStore.sendLocalPlayer(model)
                return nil
            }

            // A mismatched sender with a master-owned baseline is a request
            // for that baseline, published as the authoritative group
            // reveal — a player's competing version of a known PDF never
            // replaces the master's own.
            guard await root.pdfRoot.gameControllable.hasLocalFileData(for: model.data.id) else { return nil }
            do {
                let canonical = try await root.pdfRoot.gameControllable.createGameData(for: model.data.id)
                gameModel.markSentGameItem(
                    type: .pdf,
                    id: canonical.id,
                    version: canonical.effectiveAssetVersion
                )
                await send(
                    type: .reveal,
                    subtype: .show,
                    updated: canonical,
                    replyToMessageID: model.messageID
                )
                return nil
            } catch ItemGameStorableError.itemMissing {
                // The master has no copy at all — there is no baseline to
                // defend. Mirror handlePhoto/handleSpace's `.itemMissing`
                // import fallback: import the player's bytes as the master's
                // own canonical copy, then relay exactly what was received.
                guard model.data.data != nil else { return nil }
                try await root.pdfRoot.gameControllable.updateGame(data: model.data, hide: false, deep: false)
                gameModel.markSentGameItem(
                    type: .pdf,
                    id: model.data.id,
                    version: model.data.effectiveAssetVersion
                )
                await send(
                    type: .reveal,
                    subtype: .show,
                    updated: model.data,
                    replyToMessageID: model.messageID
                )
                return nil
            } catch {
                Logger.networking.error("MasterController: Failed to import shared PDF \(model.data.id, privacy: .public) as canonical copy: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        case .store:
            guard await root.pdfRoot.gameControllable.hasLocalFileData(for: model.data.id) else { return nil }
            return try await root.pdfRoot.gameControllable.createGameData(for: model.data.id)
        case .update:
            switch model.subType {
            case .pdfList:
                guard await applyPdfList(model) else { return nil }
                let pdfList = await root.pdfRoot.pdfGameControllable.pdfList(
                    allPlayers: true,
                    with: masterId
                )
                await send(type: .update, subtype: .pdfList, updated: pdfList)
            case .generic:
                // Compatibility with older players: answer with the canonical
                // master asset, but never import the peer's bytes.
                guard await root.pdfRoot.gameControllable.hasLocalFileData(for: model.data.id) else { return nil }
                if let canonical = try? await root.pdfRoot.gameControllable.createGameData(for: model.data.id) {
                    gameModel.markSentGameItem(
                        type: .pdf,
                        id: canonical.id,
                        version: canonical.effectiveAssetVersion
                    )
                    await send(type: .reveal, subtype: .show, updated: canonical)
                }
            default:
                break
            }
            return nil
        }
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
