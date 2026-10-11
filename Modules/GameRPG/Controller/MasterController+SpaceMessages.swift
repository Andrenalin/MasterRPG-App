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

// MARK: - Space Messages

extension MasterController {
    func handleSpace(_ model: GameNetworkModel) async throws -> NetworkCodableDataType? {
        if model.subType == .ok {
            await recordFileOkAck(
                model,
                controllable: root.spaceRoot.gameControllable,
                setMasterVersion: { root.spaceRoot.spaceGameControllable.setMasterVersion(itemId: $0, version: $1, masterId: $2) },
                markAvailable: { root.spaceRoot.spaceGameControllable.markSpaceAvailable(itemId: $0, version: $1, for: $2, masterId: $3) },
                announceList: { await broadcastSpaceList() }
            )
            return nil
        }
        guard model.subType != .failed else { return nil }

        let masterId = root.gameModel.gameConfig.id
        if model.isAssetRequest {
            // An iCloud file that has not downloaded cannot be exported.
            guard await root.spaceRoot.gameControllable.hasLocalFileData(for: model.data.id) else { return nil }
            return try await root.spaceRoot.gameControllable.createGameData(for: model.data.id)
        }
        guard model.type == .update else { return nil }

        switch model.subType {
        case .spaceList:
            guard await applySpaceList(model) else { return nil }
            await broadcastSpaceList()
        case .spaceTransform:
            guard model.isPlayerGroupEvent,
                  root.gameModel.gameControl.features.spaceSharing,
                  root.spaceRoot.spaceGameControllable.isValidSpaceTransform(model.data)
            else { return nil }

            // The transform is for the master's version of the Space only.
            let baseline = await root.spaceRoot.gameControllable.networkVersion(for: model.data.id)
            root.spaceRoot.spaceGameControllable.setMasterVersion(
                itemId: model.data.id,
                version: baseline,
                masterId: masterId
            )
            guard model.data.effectiveAssetVersion == baseline,
                  gameModel.canApplySpaceTransform(
                      from: model.sender.id,
                      itemId: model.data.id,
                      version: baseline,
                      counter: model.counter
                  )
            else { return nil }

            guard root.spaceRoot.spaceGameControllable.applySpaceTransform(
                data: model.data,
                counter: model.counter,
                timestamp: model.timestamp
            ) else { return nil }
            gameModel.recordSpaceTransform(
                from: model.sender.id,
                itemId: model.data.id,
                version: baseline,
                counter: model.counter
            )
        case .generic:
            guard model.sender.role == .player,
                  root.gameModel.gameControl.features.spaceSharing
            else { return nil }
            await showPlayerContribution(model, controllable: root.spaceRoot.gameControllable)
        default:
            break
        }
        return nil
    }

    /// Sends every player the authoritative report list: who has which version.
    private func broadcastSpaceList() async {
        let list = await root.spaceRoot.spaceGameControllable.spaceList(
            allPlayers: true,
            with: root.gameModel.gameConfig.id
        )
        await send(type: .update, subtype: .spaceList, updated: list)
    }

    private func applySpaceList(_ model: GameNetworkModel) async -> Bool {
        await applyFileList(
            model,
            canApply: { gameModel.canApplySpaceList(from: $0, counter: $1) },
            apply: { data, senderId, masterId, authoritative in
                await root.spaceRoot.spaceGameControllable.applySpaceList(
                    data: data,
                    for: senderId,
                    with: masterId,
                    authoritative: authoritative
                )
            },
            record: { gameModel.recordSpaceList(counter: $0, from: $1) }
        )
    }
}
