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
                networkVersion: { await root.photoRoot.gameControllable.networkVersion(for: $0) },
                setMasterVersion: { root.photoRoot.photoGameControllable.setMasterVersion(itemId: $0, version: $1, masterId: $2) },
                markAvailable: { root.photoRoot.photoGameControllable.markPhotoAvailable(itemId: $0, version: $1, for: $2, masterId: $3) }
            )
            return nil
        }
        guard model.subType != .failed else { return nil }

        let masterId = root.gameModel.gameConfig.id
        if model.purpose == .assetRequest {
            guard model.type == .reveal || model.type == .store else { return nil }
            return try await root.photoRoot.gameControllable.createGameData(for: model.data.id)
        }

        switch model.type {
        case .reveal:
            guard root.gameModel.gameControl.features.photoSharing else { return nil }
            let reference = await root.photoRoot.gameControllable.share(id: model.data.id)
            root.photoRoot.photoGameControllable.setMasterVersion(
                itemId: reference.id,
                version: reference.effectiveAssetVersion,
                masterId: masterId
            )
            let senderIsAvailable = root.photoRoot.photoGameControllable.isPhotoAvailable(
                itemId: model.data.id,
                for: model.sender.id,
                masterId: masterId
            )
            let matchesBaseline = model.data.effectiveAssetVersion == reference.effectiveAssetVersion

            if senderIsAvailable, matchesBaseline {
                // LAN and SharePlay forwarding already distributed the player's
                // reveal (and its Journal attachment). Only the game master's
                // co-located player controller did not receive that fan-out.
                if model.data.data != nil {
                    gameModel.markSentGameItem(
                        type: .photo,
                        id: model.data.id,
                        version: reference.effectiveAssetVersion
                    )
                }
                await root.networkStore.sendLocalPlayer(model)
                return nil
            }

            // A mismatched sender with a master-owned baseline is a request
            // for that baseline, published as the authoritative group
            // reveal — a player's competing version of a known item never
            // replaces the master's own.
            do {
                let canonical = try await root.photoRoot.gameControllable.createGameData(for: model.data.id)
                gameModel.markSentGameItem(
                    type: .photo,
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
                // The master has no copy at all — unlike a competing edit of
                // a known item, there is no baseline to defend. Mirror the
                // audio `.update/.generic` path: import the player's bytes as
                // the master's own canonical copy, then relay exactly what
                // was received so the group (and the master's own display)
                // converge on it without a redundant re-export round trip.
                guard model.data.data != nil else { return nil }
                // No import policy for the player's package: accepted, see `updateGame(data:hide:deep:)`
                // (CODE_AUDIT_Folder §6.1, won't fix).
                try await root.photoRoot.gameControllable.updateGame(data: model.data, hide: false, deep: false)
                gameModel.markSentGameItem(
                    type: .photo,
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
                // Previously this only logged, leaving the requester waiting
                // indefinitely whenever the master's local copy isn't
                // actually materialized yet (e.g. an undownloaded iCloud
                // placeholder) rather than genuinely missing. See
                // CODE_AUDIT_Network §5.12.
                Logger.networking.error("MasterController: Failed to import shared photo \(model.data.id, privacy: .public) as canonical copy: \(error.logIdentifier, privacy: .public) \(error.localizedDescription, privacy: .private)")
                await send(
                    type: .reveal,
                    subtype: .failed,
                    updated: NetworkCodableDataType(id: model.data.id, type: .photo, version: model.data.version, data: nil),
                    replyToMessageID: model.messageID,
                    playerId: model.sender.id
                )
                return nil
            }
        case .store:
            return try await root.photoRoot.gameControllable.createGameData(for: model.data.id)
        case .update:
            switch model.subType {
            case .photoList:
                guard await applyPhotoList(model) else { return nil }
                let photoList = await root.photoRoot.photoGameControllable.photoList(
                    allPlayers: true,
                    with: masterId
                )
                await send(type: .update, subtype: .photoList, updated: photoList)
            case .generic:
                // A player names a photo the master has while another player
                // misses it (`PlayerController.shareFileItem`): the master
                // broadcasts its canonical copy. Older players uploaded their
                // bytes here; those are never authoritative.
                guard root.gameModel.gameControl.features.photoSharing else { return nil }
                if let canonical = try? await root.photoRoot.gameControllable.createGameData(for: model.data.id) {
                    gameModel.markSentGameItem(
                        type: .photo,
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
