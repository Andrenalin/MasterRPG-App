// @copyright André Trettin

import CoreRPG
import Foundation
import MapRPG

// Split out of PlayerController+Map.swift — presentation plus
// deferred-pin/battle-round replay. See CODE_AUDIT_Game §9.9.

extension PlayerController {
    func presentMap(itemId: UUID) async {
        _ = await root.mapRoot.gameControllable.setCurrent(itemId: itemId)
        if root.gameModel.gameConfig.isMaster {
            _ = root.mapRoot.mapGameControllable.synchronizePlayerPins(for: itemId)
            // Pin reconciliation just above can change this map's structural
            // content right after this reveal recorded its generation's
            // fingerprint. Refresh it so the game master's own co-located
            // screen keeps recognizing this exact, unedited map on a later
            // reference-only reshow instead of chasing a phantom repair.
            root.mapRoot.mapGameControllable.refreshAuthoritativeMapContentVersion(for: itemId)
        }
        retryDeferredMapPins(itemId: itemId)
        retryDeferredBattleRoundUpdate(itemId: itemId)
        gameModel.setGameUpdateType(.map)
        await refreshMapVisuals(itemId: itemId)
    }

    func applyPlayerMapPin(_ model: GameNetworkModel) -> PlayerMapPinApplication {
        guard root.mapRoot.gameControllable.gameModel.currentItemId == model.data.id else {
            return .awaitingMapGeneration
        }
        let generation = root.mapRoot.mapGameControllable.networkMapUpdate(for: model.data.id)
        guard model.data.version == generation.version,
              model.data.assetVersion == generation.assetVersion,
              model.data.contentVersion == generation.contentVersion
        else {
            return .awaitingMapGeneration
        }
        guard root.mapRoot.mapGameControllable.updatePinIfCurrentGeneration(
            itemId: model.data.id,
            data: model.data,
            playerId: model.sender.id
        ) else {
            return .rejected
        }

        // Runs on every device that mirrors this `.mapPin` broadcast — a
        // player device included. Only the master may let this recompute/
        // persist `pin.healthPercent`; on a player's own device it's a
        // guaranteed no-op (see `synchronizeBattleDefenders`'s doc comment).
        _ = root.mapRoot.mapGameControllable.synchronizeBattleDefenders(
            itemId: model.data.id,
            isGameMaster: root.gameModel.gameConfig.isMaster
        )
        #if !os(tvOS)
        root.gameModel.gameTableModel?.syncPawnsWithMapPins()
        #endif
        return .applied
    }

    /// Replays a `.battleRound` update that was previously deferred by a map
    /// generation mismatch. Called at the same points as
    /// `retryDeferredMapPins(itemId:)` below — right after this device's map
    /// generation just moved forward — since `applyBattleRoundUpdate` itself
    /// re-validates the generation and the state's own sequence number
    /// before applying anything. See CODE_AUDIT §5.2.
    func retryDeferredBattleRoundUpdate(itemId: UUID) {
        guard root.mapRoot.gameControllable.gameModel.currentItemId == itemId,
              let data = gameModel.pendingBattleRoundUpdate(for: itemId) else { return }
        guard root.mapRoot.mapGameControllable.applyBattleRoundUpdate(for: itemId, with: data) else { return }
        gameModel.discardPendingBattleRoundUpdate(itemId: itemId)
        setMapUpdateTypeAndSyncPawns()
    }

    func retryDeferredMapPins(itemId: UUID) {
        guard root.mapRoot.gameControllable.gameModel.currentItemId == itemId else { return }
        let generation = root.mapRoot.mapGameControllable.networkMapUpdate(for: itemId)
        let deferred = gameModel.consumeDeferredMapPins(for: itemId, matching: generation)
        var didApplyPin = false
        for model in deferred {
            didApplyPin = root.mapRoot.mapGameControllable.updatePinIfCurrentGeneration(
                itemId: itemId,
                data: model.data,
                playerId: model.sender.id
            ) || didApplyPin
        }
        guard didApplyPin else { return }

        // Same reasoning as `applyPlayerMapPin` above: a no-op unless this
        // device is the master.
        _ = root.mapRoot.mapGameControllable.synchronizeBattleDefenders(
            itemId: itemId,
            isGameMaster: root.gameModel.gameConfig.isMaster
        )
        #if !os(tvOS)
        root.gameModel.gameTableModel?.syncPawnsWithMapPins()
        #endif
    }

    func refreshMapVisuals(itemId: UUID) async {
        // mapState carries pin metadata but not newly referenced photo models.
        // The background itself remains exclusive to the full Map package.
        await requestMissingMapImages(itemId: itemId)
        #if !os(tvOS)
        let isGameMaster = root.gameModel.gameConfig.isMaster
        await root.gameModel.gameTableModel?.refreshFogOfWar(isGameMaster: isGameMaster)
        root.gameModel.gameTableModel?.syncPawnsWithMapPins()
        #endif
    }
}
