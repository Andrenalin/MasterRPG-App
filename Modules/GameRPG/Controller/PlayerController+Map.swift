// @copyright André Trettin

import CoreRPG
import Foundation
import MapRPG

// A map travels like every file-backed item: the game master names it, a player that lacks it
// answers with the same counter and gets the package. What changes while the map is shown
// (content, state, battle round, pins) follows as small updates.

extension PlayerController {
    func handleMap(_ model: GameNetworkModel) async throws -> GameNetworkModel? {
        guard !model.isAcknowledgement else { return nil }

        if model.isPlayerGroupEvent {
            // Another player moved its pin.
            applyPlayerMapPin(model)
            return nil
        }

        guard model.sender.isMaster else { return nil }

        if root.gameModel.gameConfig.isMaster {
            // The game master's own co-located screen (and any external
            // display reading the same state) is always seeing its own
            // broadcast here: master and player share one `GameRoot`, so
            // `model.data` merely echoes state this device's `root.mapRoot`
            // already holds as the single source of truth.
            return await handleLocalMasterMap(model)
        }

        switch model.type {
        case .reveal:
            return try await receiveMap(model, presents: true)
        case .store:
            return try await receiveMap(model, presents: false)
        case .update:
            switch model.subType {
            case .generic:
                return await handleMapContentUpdate(model)
            case .mapState:
                return await handleMapState(model)
            case .battleRound:
                // An update for a map that is not there yet waits for it.
                guard root.mapRoot.mapGameControllable.applyBattleRoundUpdate(
                    for: model.data.id,
                    with: model.data
                ) else {
                    gameModel.mapUpdates.queueBattleRoundUpdate(model.data)
                    return nil
                }
                gameModel.mapUpdates.discardPendingBattleRoundUpdate(itemId: model.data.id)
                setMapUpdateTypeAndSyncPawns()
            default:
                break
            }
            return nil
        }
    }

    /// A reveal shows the map, a store only keeps it. Either names the map or carries its
    /// package.
    private func receiveMap(_ model: GameNetworkModel, presents: Bool) async throws -> GameNetworkModel? {
        let itemId = model.data.id
        let holdsMap = await holdsMap(model.data)

        if model.data.data != nil {
            // A package that arrives after a newer content update would roll the map back.
            if !holdsMap || gameModel.mapUpdates.shouldApplyMapContentUpdate(itemId: itemId, counter: model.counter) {
                // The master is unconditionally authoritative for map state — `.overwrite`
                // skips the default last-writer-wins merge, which is keyed on each device's
                // own wall clock and can let this player's stale copy of the map win over
                // what the master just sent. See player-character-sync-gaps memory note.
                try await root.mapRoot.gameControllable.updateGame(
                    data: model.data,
                    hide: true,
                    deep: !presents,
                    importMode: .overwrite
                )
                root.mapRoot.mapGameControllable.recordAuthoritativeMapGeneration(model.data)
                gameModel.mapUpdates.markMapContentApplied(itemId: itemId, counter: model.counter)
            }
            guard await root.mapRoot.mapGameControllable.hasBackgroundImage(itemId: itemId) else {
                // Never acknowledge or show a map without its background.
                return await response(for: model, isSuccess: false, requestData: false)
            }
        } else {
            let isUsable: Bool
            if holdsMap {
                isUsable = await root.mapRoot.mapGameControllable.hasBackgroundImage(itemId: itemId)
            } else {
                isUsable = false
            }
            guard isUsable else {
                gameModel.clearGameUpdateTypeIfPhoto()
                gameModel.mapUpdates.noteMapRequest(itemId: itemId)
                return await response(for: model, isSuccess: true, requestData: true)
            }
        }

        await applyPendingMapUpdates(itemId: itemId)
        if presents {
            await presentMap(itemId: itemId)
        } else {
            await requestMissingMapImages(itemId: itemId)
        }
        return await response(for: model, isSuccess: true, requestData: false)
    }

    /// Whether this player holds the map with the background the message names.
    private func holdsMap(_ data: NetworkCodableDataType) async -> Bool {
        guard await root.mapRoot.gameControllable.hasItem(id: data.id, version: 0) else { return false }
        guard let assetVersion = data.assetVersion else { return true }
        return await root.mapRoot.mapGameControllable.mapAssetVersion(for: data.id) == assetVersion
    }

    /// Applies the content, state and battle round that arrived before their map.
    private func applyPendingMapUpdates(itemId: UUID) async {
        if let pending = gameModel.mapUpdates.pendingMapContentUpdate(for: itemId) {
            if gameModel.mapUpdates.shouldApplyMapContentUpdate(itemId: itemId, counter: pending.counter),
               root.mapRoot.mapGameControllable.applyMapContentUpdate(for: itemId, with: pending.data) {
                gameModel.mapUpdates.markMapContentApplied(itemId: itemId, counter: pending.counter)
            } else {
                gameModel.mapUpdates.discardPendingMapContentUpdate(itemId: itemId)
            }
        }
        if let pending = gameModel.mapUpdates.pendingMapState(for: itemId) {
            if gameModel.mapUpdates.shouldApplyMapState(itemId: itemId, counter: pending.counter),
               root.mapRoot.mapGameControllable.updateMap(for: itemId, with: pending.data) {
                gameModel.mapUpdates.markMapStateApplied(itemId: itemId, counter: pending.counter)
            } else {
                gameModel.mapUpdates.discardPendingMapState(itemId: itemId)
            }
        }
        retryDeferredBattleRoundUpdate(itemId: itemId)
    }

    private func handleMapState(_ model: GameNetworkModel) async -> GameNetworkModel? {
        let itemId = model.data.id
        guard model.data.data != nil,
              gameModel.mapUpdates.shouldApplyMapState(itemId: itemId, counter: model.counter)
        else { return nil }

        guard await holdsMap(model.data) else {
            // The state of a map this player lacks: it waits for the map, which is asked for
            // with the state's counter. A burst of states asks once.
            gameModel.mapUpdates.queueMapState(model.data, counter: model.counter)
            guard gameModel.mapUpdates.mayRequestMap(itemId: itemId) else { return nil }
            return root.gameModel.outgoingMessage(
                counter: model.counter,
                proxyCounter: model.proxyCounter,
                type: .reveal,
                subType: .show,
                asMaster: false,
                data: model.data.reference
            )
        }

        guard root.mapRoot.mapGameControllable.updateMap(for: itemId, with: model.data) else { return nil }
        gameModel.mapUpdates.markMapStateApplied(itemId: itemId, counter: model.counter)
        retryDeferredBattleRoundUpdate(itemId: itemId)
        gameModel.showMapForLiveUpdate(of: itemId)
        await refreshMapVisuals(itemId: itemId)
        return nil
    }

    /// Handles every Map message `handleMap` routes here because
    /// `root.gameModel.gameConfig.isMaster` is true — i.e. this
    /// `PlayerController` is the game master's own co-located mirror,
    /// talking to itself. `root.mapRoot` is this device's single source of
    /// truth for the map regardless of any message describing it, so this
    /// never imports, compares generations, or requests a repair: it only
    /// ever updates this controller's own presentation bookkeeping
    /// (`gameUpdateType`, the current map, visuals) to match what the
    /// master already broadcast.
    private func handleLocalMasterMap(_ model: GameNetworkModel) async -> GameNetworkModel? {
        switch model.type {
        case .reveal, .store:
            await presentMap(itemId: model.data.id)
            return await response(for: model, isSuccess: true, requestData: false)
        case .update:
            switch model.subType {
            case .mapState:
                retryDeferredBattleRoundUpdate(itemId: model.data.id)
                gameModel.showMapForLiveUpdate(of: model.data.id)
                await refreshMapVisuals(itemId: model.data.id)
            case .battleRound:
                setMapUpdateTypeAndSyncPawns()
            case .generic, .mapPin:
                // A structural/content resync or a player-authored pin move:
                // this device's own map already reflects it. Neither one is
                // a presentation intent on its own (`.generic` in particular
                // must not force the map to the front over whatever the
                // master currently has shown, e.g. a Photo).
                break
            default:
                break
            }
            return nil
        }
    }

    func handleMapContentUpdate(_ model: GameNetworkModel) async -> GameNetworkModel? {
        let itemId = model.data.id
        guard model.sender.isMaster,
              model.data.type == .map,
              model.data.data != nil,
              gameModel.mapUpdates.shouldApplyMapContentUpdate(itemId: itemId, counter: model.counter)
        else { return nil }

        guard await holdsMap(model.data) else {
            // Content alone shows nothing. It waits for the map, which the reveal or the
            // state that follows asks for.
            gameModel.mapUpdates.queueMapContentUpdate(model.data, counter: model.counter)
            return nil
        }

        guard root.mapRoot.mapGameControllable.applyMapContentUpdate(for: itemId, with: model.data) else {
            return nil
        }
        gameModel.mapUpdates.markMapContentApplied(itemId: itemId, counter: model.counter)
        await applyPendingMapUpdates(itemId: itemId)
        await refreshMapVisuals(itemId: itemId)
        return nil
    }
}
