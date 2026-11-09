// @copyright André Trettin

import CoreRPG
import Foundation
import os.log
import AdventureRPG
import AudioRPG
import CharacterRPG
import DiceRPG
import MapRPG
import PdfRPG
import PhotoRPG
import SpaceRPG
import TableRPG
import WeatherRPG

// MARK: - Map Messages

extension MasterController {
#if DEBUG
    /// A test affordance: real dispatch always goes through `handle(_:origin:)`, which calls
    /// the `origin`-based overload below directly.
    func handleMap(
        _ model: GameNetworkModel,
        connectionId: ConnectionController.ID? = nil
    ) async throws -> NetworkCodableDataType? {
        try await handleMap(
            model,
            origin: connectionId.map { GameMessageOrigin.direct($0) }
        )
    }
#endif

    /// Not `private` because `MasterController+MessageDispatch.swift`'s
    /// `handle(_:origin:)` also calls this directly, from a different file.
    func handleMap(
        _ model: GameNetworkModel,
        origin: GameMessageOrigin?
    ) async throws -> NetworkCodableDataType? {
        // Maps are session-memory presentations, not player-owned assets.
        // Acknowledgements therefore carry no availability meaning.
        guard !model.isAcknowledgement else { return nil }

        if model.isAssetRequest {
            // A paused "Share Map" keeps the map private: the package is captured from the live
            // game map and carries what was revealed privately. The player asks again when
            // sharing resumes and the content and state go out.
            guard mayShareMapState(for: model.data.id) else {
                Logger.networking.debug("MasterController: Map request for \(model.data.id, privacy: .public) not answered while map sharing is paused")
                return nil
            }
            let package = try await cachedMapPackage(for: model.data.id)
            await send(
                type: .reveal,
                subtype: .show,
                updated: package,
                counter: model.counter,
                origin: origin,
                authoritativeMaster: true
            )
            // The package is followed by the live map, so the player syncs room visibility
            // and pins. Only the requester needs it: everyone else is up to date.
            await sendMapFollowUps(for: model.data.id, origin: origin, playerId: model.sender.id)
            return nil
        }

        if model.sender.role == .observer {
            await applyObserverPinMove(model)
            return nil
        }

        guard model.type == .update,
              model.subType == .mapPin,
              model.isPlayerGroupEvent
        else { return nil }

        if root.mapRoot.mapGameControllable.updatePinIfCurrentGeneration(
            itemId: model.data.id,
            data: model.data,
            playerId: model.sender.id
        ) {
            // `updatePinIfCurrentGeneration` never copies the sender's
            // `healthPercent` (only location/isPhotoShared/isHighlighted) —
            // the master is the sole authority for it. Recomputing it
            // here (e.g. a player highlighting a new target) only
            // updates the master's own authoritative copy; without
            // rebroadcasting, every player — including the one who
            // just highlighted the pin — keeps showing the stale
            // value until an unrelated battle action happens to
            // broadcast next.
            let syncResult = root.mapRoot.mapGameControllable.synchronizeBattleDefenders(
                itemId: model.data.id,
                isGameMaster: true
            )
            #if !os(tvOS)
            root.gameModel.gameTableModel?.syncPawnsWithMapPins()
            #endif
            if syncResult.healthChanged {
                // A paused "Share Map" keeps the map state private; only the battle
                // round goes out. See CODE_AUDIT_19 §5.7.
                if root.mapRoot.rootModel.isMapStreaming {
                    await send(
                        type: .update,
                        subtype: .mapState,
                        updated: root.mapRoot.mapGameControllable.networkMapUpdate(for: model.data.id),
                        authoritativeMaster: true
                    )
                }
                if let battleUpdate = root.mapRoot.mapGameControllable.networkBattleRoundUpdate(
                    for: model.data.id
                ) {
                    await send(
                        type: .update,
                        subtype: .battleRound,
                        updated: battleUpdate,
                        authoritativeMaster: true
                    )
                }
            }
        }
        return nil
    }

    /// An observer moved a player pin the game master gave it. Unlike a player's move it is no
    /// group event (nobody relays it), so the master applies it and sends the map state to
    /// everyone. An observer may only move such a pin: no pointer, no other pin.
    private func applyObserverPinMove(_ model: GameNetworkModel) async {
        guard model.type == .update,
              model.subType == .mapPin,
              model.data.type == .map,
              let incoming = MapPinModel.decodeData(of: model.data.data),
              let map = root.mapRoot.gameControllable.gameModel.itemData[model.data.id] as? MapModel,
              map.mapPins.first(where: { $0.id == incoming.id })?.isControlled(by: model.sender.id) == true,
              root.mapRoot.mapGameControllable.updatePinIfCurrentGeneration(
                  itemId: model.data.id,
                  data: model.data,
                  playerId: model.sender.id
              )
        else { return }

        _ = root.mapRoot.mapGameControllable.synchronizeBattleDefenders(
            itemId: model.data.id,
            isGameMaster: true
        )
        #if !os(tvOS)
        root.gameModel.gameTableModel?.syncPawnsWithMapPins()
        #endif
        guard mayShareMapState(for: model.data.id) else { return }
        await send(
            type: .update,
            subtype: .mapState,
            updated: root.mapRoot.mapGameControllable.networkMapUpdate(for: model.data.id),
            authoritativeMaster: true
        )
    }

    /// Whether the map's content and live state (room visibility, focus, pins) may go out now.
    /// A paused "Share Map" keeps them private: the map is marked as having unshared structure,
    /// and resuming or "Refresh Shared Map" sends everything. Every master send of map content or
    /// state that is not an explicit refresh goes through this check.
    /// See CODE_AUDIT_19 §5.7, CODE_AUDIT_20 §5.2.
    func mayShareMapState(for mapId: UUID) -> Bool {
        guard !root.mapRoot.rootModel.isMapStreaming else { return true }
        root.mapRoot.rootModel.mapsWithUnsharedStructure.insert(mapId)
        return false
    }
}
