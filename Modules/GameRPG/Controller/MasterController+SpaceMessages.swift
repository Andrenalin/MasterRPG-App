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
                networkVersion: { await root.spaceRoot.gameControllable.networkVersion(for: $0) },
                setMasterVersion: { root.spaceRoot.spaceGameControllable.setMasterVersion(itemId: $0, version: $1, masterId: $2) },
                markAvailable: { root.spaceRoot.spaceGameControllable.markSpaceAvailable(itemId: $0, version: $1, for: $2, masterId: $3) }
            )
            return nil
        }
        guard model.subType != .failed else { return nil }

        let masterId = root.gameModel.gameConfig.id
        if model.purpose == .assetRequest {
            guard model.type == .reveal || model.type == .store,
                  await root.spaceRoot.gameControllable.hasLocalFileData(for: model.data.id)
            else { return nil }
            return try await root.spaceRoot.gameControllable.createGameData(for: model.data.id)
        }

        switch model.type {
        case .reveal:
            let playerSharingEnabled = root.gameModel.gameControl.features.spaceSharing
            let reference = await root.spaceRoot.gameControllable.share(id: model.data.id)
            root.spaceRoot.spaceGameControllable.setMasterVersion(
                itemId: reference.id,
                version: reference.effectiveAssetVersion,
                masterId: masterId
            )
            let senderIsAvailable = root.spaceRoot.spaceGameControllable.isSpaceAvailable(
                itemId: model.data.id,
                for: model.sender.id,
                masterId: masterId
            )
            let matchesBaseline = model.data.effectiveAssetVersion == reference.effectiveAssetVersion

            if playerSharingEnabled, senderIsAvailable, matchesBaseline {
                if model.data.data != nil {
                    gameModel.markSentGameItem(
                        type: .space,
                        id: model.data.id,
                        version: reference.effectiveAssetVersion
                    )
                }
                // The transport already delivered the peer reveal to remote
                // participants. Only the co-located player missed that fan-out.
                await root.networkStore.sendLocalPlayer(model)
                return nil
            }

            if !playerSharingEnabled {
                // `spaceSharing` controls player-initiated presentations, not
                // delivery of a Space the master already presented. A player
                // missing the Journal attachment answers the master's reveal
                // with this data-less request. Return the canonical package so
                // the common request path targets it only at that player.
                guard model.data.data == nil, matchesBaseline else { return nil }
                return try? await root.spaceRoot.gameControllable.createGameData(for: model.data.id)
            }

            // A mismatched sender with a master-owned baseline is a request
            // for that baseline, published as the authoritative group
            // reveal — a player's competing version of a known Space never
            // replaces the master's own.
            do {
                let canonical = try await root.spaceRoot.gameControllable.createGameData(for: model.data.id)
                gameModel.markSentGameItem(
                    type: .space,
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
                // The master has no copy at all — this is the player-sharing
                // path (`playerSharingEnabled` above), so unlike a competing
                // edit of a known Space, there is no baseline to defend.
                // Mirror handlePhoto/handleAudio's `.update/.generic` path:
                // import the player's bytes as the master's own canonical
                // copy, then relay exactly what was received so the group
                // (and the master's own display) converge on it without a
                // redundant re-export round trip.
                guard model.data.data != nil else { return nil }
                // No import policy for the player's package: accepted, see `updateGame(data:hide:deep:)`
                // (CODE_AUDIT_Folder §6.1, won't fix).
                try await root.spaceRoot.gameControllable.updateGame(data: model.data, hide: false, deep: false)
                gameModel.markSentGameItem(
                    type: .space,
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
                Logger.networking.error("MasterController: Failed to import shared space \(model.data.id, privacy: .public) as canonical copy: \(error.localizedDescription, privacy: .public)")
                await send(
                    type: .reveal,
                    subtype: .failed,
                    updated: NetworkCodableDataType(id: model.data.id, type: .space, version: model.data.version, data: nil),
                    replyToMessageID: model.messageID,
                    playerId: model.sender.id
                )
                return nil
            }
        case .store:
            return try await root.spaceRoot.gameControllable.createGameData(for: model.data.id)
        case .update:
            switch model.subType {
            case .spaceList:
                guard await applySpaceList(model) else { return nil }
                let spaceList = await root.spaceRoot.spaceGameControllable.spaceList(
                    allPlayers: true,
                    with: masterId
                )
                await send(type: .update, subtype: .spaceList, updated: spaceList)
            case .spaceTransform:
                guard model.sender.role == .player,
                      model.purpose == .event,
                      model.effectiveAudience == .group,
                      root.gameModel.gameControl.features.spaceSharing,
                      root.spaceRoot.spaceGameControllable.isValidSpaceTransform(model.data)
                else { return nil }

                let baseline = await root.spaceRoot.gameControllable.networkVersion(for: model.data.id)
                root.spaceRoot.spaceGameControllable.setMasterVersion(
                    itemId: model.data.id,
                    version: baseline,
                    masterId: masterId
                )
                guard model.data.effectiveAssetVersion == baseline,
                      root.spaceRoot.spaceGameControllable.isSpaceAvailable(
                          itemId: model.data.id,
                          for: model.sender.id,
                          masterId: masterId
                      ),
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
                // Compatibility with older players. Peer bytes never replace the
                // game master's canonical Space asset.
                guard root.gameModel.gameControl.features.spaceSharing else { return nil }
                if let canonical = try? await root.spaceRoot.gameControllable.createGameData(for: model.data.id) {
                    gameModel.markSentGameItem(
                        type: .space,
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
