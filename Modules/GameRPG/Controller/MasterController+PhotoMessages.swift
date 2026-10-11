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

// MARK: - Photo Messages

extension MasterController {
    func handlePhoto(_ model: GameNetworkModel) async throws -> NetworkCodableDataType? {
        if model.subType == .ok {
            await recordFileOkAck(
                model,
                controllable: root.photoRoot.gameControllable,
                setMasterVersion: { root.photoRoot.photoGameControllable.setMasterVersion(itemId: $0, version: $1, masterId: $2) },
                markAvailable: { root.photoRoot.photoGameControllable.markPhotoAvailable(itemId: $0, version: $1, for: $2, masterId: $3) },
                announceList: { await broadcastPhotoList() }
            )
            return nil
        }
        guard model.subType != .failed else { return nil }

        if model.isAssetRequest {
            // An iCloud file that has not downloaded cannot be exported.
            guard await root.photoRoot.gameControllable.hasLocalFileData(for: model.data.id) else { return nil }
            return try await root.photoRoot.gameControllable.createGameData(for: model.data.id)
        }
        guard model.type == .update else { return nil }

        switch model.subType {
        case .photoList:
            guard await applyPhotoList(model) else { return nil }
            await broadcastPhotoList()
        case .generic:
            guard model.sender.role == .player,
                  root.gameModel.gameControl.features.photoSharing
            else { return nil }
            await showPlayerContribution(model, controllable: root.photoRoot.gameControllable)
        default:
            break
        }
        return nil
    }

    /// Sends every player the authoritative report list: who has which version.
    private func broadcastPhotoList() async {
        let list = await root.photoRoot.photoGameControllable.photoList(
            allPlayers: true,
            with: root.gameModel.gameConfig.id
        )
        await send(type: .update, subtype: .photoList, updated: list)
    }

    private func applyPhotoList(_ model: GameNetworkModel) async -> Bool {
        await applyFileList(
            model,
            canApply: { gameModel.canApplyPhotoList(from: $0, counter: $1) },
            apply: { data, senderId, masterId, authoritative in
                await root.photoRoot.photoGameControllable.applyPhotoList(
                    data: data,
                    for: senderId,
                    with: masterId,
                    authoritative: authoritative
                )
            },
            record: { gameModel.recordPhotoList(counter: $0, from: $1) }
        )
    }
}
