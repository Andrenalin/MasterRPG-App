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

struct MapRecoveryThrottleKey: Hashable {
    let playerId: UUID
    let itemId: UUID
}

// MARK: - Map Messages

extension MasterController {
    private struct MapRecoveryBundle: Sendable {
        let full: NetworkCodableDataType
        let content: NetworkCodableDataType
        let state: NetworkCodableDataType
    }

    private enum MapRecoveryError: Error {
        case generationChanged
    }

    /// The outermost of three nested retry levels — see
    /// `MapRPG.GameController.maximumPackageExportAttempts`'s doc comment for
    /// the full compounding chain. See CODE_AUDIT_Game §9.13.
    private static let maximumMapRecoveryCaptureAttempts = 3

    /// Test affordance — real dispatch always goes through `handle(_:origin:)`,
    /// which calls the `origin`-based overload below directly. Kept as the
    /// entry point the extensive `MapPlayerSequencingTests`/`MapMasterMessageFlowTests`
    /// suites already use. See CODE_AUDIT_Game §9.22.
    func handleMap(
        _ model: GameNetworkModel,
        connectionId: ConnectionController.ID? = nil
    ) async throws -> NetworkCodableDataType? {
        try await handleMap(
            model,
            origin: connectionId.map { GameMessageOrigin.direct($0) }
        )
    }

    /// Not `private` because `MasterController+MessageDispatch.swift`'s
    /// `handle(_:origin:)` also calls this directly, from a different file.
    func handleMap(
        _ model: GameNetworkModel,
        origin: GameMessageOrigin?
    ) async throws -> NetworkCodableDataType? {
        if model.subType == .ok {
            // Maps are session-memory presentations, not player-owned assets.
            // Acknowledgements therefore carry no availability meaning and
            // must not populate the generic player-report store.
            return nil
        }
        guard model.subType != .failed else { return nil }

        switch model.type {
        case .reveal:
            guard let recovery = try await recoverMapBundleOrFail(for: model, origin: origin) else { return nil }
            guard mapGeneration(of: recovery.full, matches: model.data) else {
                // The requested generation disappeared while the player was
                // asking for it. A proxy must defer to the real master; the
                // real master explicitly publishes its new generation so the
                // requester supersedes the now-impossible pending repair.
                guard !asProxy else { throw MapRecoveryError.generationChanged }
                await sendFreshMapRecovery(recovery, origin: origin)
                return nil
            }
            if model.subType == .mapState {
                // Targeted at the recovering player: everyone else already has
                // the map, and over SharePlay an untargeted full payload would
                // be skipped as identical to the published journal attachment.
                await send(
                    type: .reveal,
                    subtype: .store,
                    updated: recovery.full,
                    origin: origin,
                    playerId: model.sender.id,
                    authoritativeMaster: true
                )
                // Send the live map state (not the request echo, whose data is
                // nil) so the recovering player syncs room visibility and pins.
                // Targeted: the other players are already up to date.
                await send(
                    type: .update,
                    subtype: .generic,
                    updated: recovery.content,
                    origin: origin,
                    playerId: model.sender.id,
                    authoritativeMaster: true
                )
                await send(
                    type: .update,
                    subtype: .mapState,
                    updated: recovery.state,
                    origin: origin,
                    playerId: model.sender.id,
                    authoritativeMaster: true
                )
                if let battleUpdate = root.mapRoot.mapGameControllable.networkBattleRoundUpdate(
                    for: model.data.id
                ), root.mapRoot.mapGameControllable.battleRoundModel.isRunning {
                    await send(
                        type: .update,
                        subtype: .battleRound,
                        updated: battleUpdate,
                        origin: origin,
                        playerId: model.sender.id,
                        authoritativeMaster: true
                    )
                }
            } else {
                return recovery.full
            }
        case .store:
            break
        case .update:
            let observerContentRepair = model.senderType == .observer &&
                model.purpose == .assetRequest &&
                model.subType == .generic &&
                model.data.data == nil
            guard model.senderType != .observer || observerContentRepair else { return nil }
            switch model.subType {
            case .generic:
                // A data-less generic map update is a repair request for the
                // latest photo-free structural snapshot. The normal response
                // path targets the small chunked answer at the requester.
                guard model.data.data == nil else { return nil }
                let update = await root.mapRoot.mapGameControllable.networkMapContentUpdate(
                    for: model.data.id
                )
                guard mapGeneration(of: update, matches: model.data) else {
                    guard !asProxy else { throw MapRecoveryError.generationChanged }
                    guard let bundle = try await recoverMapBundleOrFail(for: model, origin: origin) else { return nil }
                    await sendFreshMapRecovery(bundle, origin: origin)
                    return nil
                }
                return update
            case .mapState:
                // never get from players mapState updates, only as resend from SharePlay?
                break
            case .mapPin:
                guard model.sender.role == .player,
                      model.purpose == .event,
                      model.effectiveAudience == .group
                else { return nil }
                if root.mapRoot.mapGameControllable.updatePinIfCurrentGeneration(
                    itemId: model.data.id,
                    data: model.data,
                    playerId: model.sender.id
                ) {
                    // `updatePinIfCurrentGeneration` never copies the sender's
                    // `healthPercent` (only location/isZoom/isHighlighted) —
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
                        await send(
                            type: .update,
                            subtype: .mapState,
                            updated: root.mapRoot.mapGameControllable.networkMapUpdate(for: model.data.id),
                            authoritativeMaster: true
                        )
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
            default:
                break
            }
        }
        return nil
    }

    /// Cool-down between full map-recovery bundles served to the same (player, map)
    /// pair. See CODE_AUDIT_17 §6.7.
    private static let mapRecoveryCooldown: Duration = .seconds(10)
    /// Per-player budget across all maps: at most `mapRecoveryBudget` full bundles per
    /// `mapRecoveryWindow`. See CODE_AUDIT_18 §6.1.
    private static let mapRecoveryWindow: Duration = .seconds(30)
    private static let mapRecoveryBudget = 3
    /// Deferred repairs a single player may have waiting; further throttled requests are
    /// answered with `.failed` instead of queuing more exports.
    private static let maximumDeferredMapRecoveriesPerPlayer = 2

    /// How long `playerId` must wait before `itemId` may be served again, or `nil` if it
    /// may be served now.
    private func mapRecoveryDelay(for key: MapRecoveryThrottleKey, now: ContinuousClock.Instant) -> Duration? {
        var delay: Duration = .zero
        if let last = gameModel.lastMapRecoveryServed[key] {
            delay = max(delay, Self.mapRecoveryCooldown - (now - last))
        }
        let recent = (gameModel.mapRecoveryHistory[key.playerId] ?? []).filter { now - $0 < Self.mapRecoveryWindow }
        if recent.count >= Self.mapRecoveryBudget, let oldest = recent.first {
            delay = max(delay, Self.mapRecoveryWindow - (now - oldest))
        }
        return delay > .zero ? delay : nil
    }

    private func recordMapRecoveryServed(_ key: MapRecoveryThrottleKey) {
        let now = ContinuousClock.now
        gameModel.lastMapRecoveryServed[key] = now
        var recent = (gameModel.mapRecoveryHistory[key.playerId] ?? []).filter { now - $0 < Self.mapRecoveryWindow }
        recent.append(now)
        gameModel.mapRecoveryHistory[key.playerId] = recent
    }

    /// Serves a throttled repair once its window opens instead of dropping it: the player
    /// tracks one pending repair per map and would otherwise wait forever. Coalesced per
    /// (player, map); the re-run goes through `handleMap` so it re-checks the throttle and
    /// the current map generation. See CODE_AUDIT_18 §6.1.
    private func deferMapRecovery(
        _ model: GameNetworkModel,
        origin: GameMessageOrigin?,
        key: MapRecoveryThrottleKey,
        after delay: Duration
    ) async {
        guard gameModel.deferredMapRecoveries[key] == nil else { return }
        let pendingForPlayer = gameModel.deferredMapRecoveries.keys.filter { $0.playerId == key.playerId }.count
        guard pendingForPlayer < Self.maximumDeferredMapRecoveriesPerPlayer else {
            await sendMapRecoveryFailed(for: model, origin: origin)
            return
        }
        gameModel.deferredMapRecoveries[key] = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard let self, !Task.isCancelled else { return }
            self.gameModel.deferredMapRecoveries[key] = nil
            do {
                if let result = try await self.handleMap(model, origin: origin) {
                    await self.send(
                        type: model.type,
                        subtype: model.subType,
                        updated: result,
                        origin: origin,
                        playerId: model.sender.id
                    )
                }
            } catch {
                Logger.networking.error("MasterController: Deferred map recovery failed for \(model.data.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func sendMapRecoveryFailed(for model: GameNetworkModel, origin: GameMessageOrigin?) async {
        await send(
            type: model.type,
            subtype: .failed,
            updated: NetworkCodableDataType(id: model.data.id, type: .map, version: model.data.version, data: nil),
            origin: origin,
            playerId: model.sender.id,
            authoritativeMaster: true
        )
    }

    /// Wraps `stableMapRecoveryBundle`, converting an exhausted-retries
    /// failure into an explicit `.failed` response sent to the requester
    /// instead of letting it propagate to the generic catch-all in
    /// `process(_:)`, which only logs and sends nothing back — leaving the
    /// requester waiting indefinitely on a persistent (not merely transient
    /// capture-window) export failure, e.g. an undownloaded iCloud
    /// background image. `CancellationError` still propagates so callers'
    /// own cancellation handling is unaffected. See CODE_AUDIT_Network §5.11.
    private func recoverMapBundleOrFail(
        for model: GameNetworkModel,
        origin: GameMessageOrigin?
    ) async throws -> MapRecoveryBundle? {
        let throttleKey = MapRecoveryThrottleKey(playerId: model.sender.id, itemId: model.data.id)
        if let delay = mapRecoveryDelay(for: throttleKey, now: .now) {
            Logger.networking.debug("MasterController: Deferring throttled map recovery request from \(model.sender.id, privacy: .public) for \(model.data.id, privacy: .public)")
            await deferMapRecovery(model, origin: origin, key: throttleKey, after: delay)
            return nil
        }
        do {
            let bundle = try await stableMapRecoveryBundle(for: model.data.id)
            // Counted only once an export actually succeeded, so a failed export doesn't
            // throttle the player's retry. See CODE_AUDIT_18 §6.1.
            recordMapRecoveryServed(throttleKey)
            return bundle
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            Logger.networking.error("MasterController: Map recovery failed for \(model.data.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            await sendMapRecoveryFailed(for: model, origin: origin)
            return nil
        }
    }

    /// Captures the full package, structural snapshot, and live state from one
    /// Map generation. Each component suspends independently, so compare their
    /// fingerprints and retry instead of sending a torn recovery sequence.
    private func stableMapRecoveryBundle(for itemId: UUID) async throws -> MapRecoveryBundle {
        let mapControllable = root.mapRoot.mapGameControllable
        for _ in 0..<Self.maximumMapRecoveryCaptureAttempts {
            try Task.checkCancellation()
            let full: NetworkCodableDataType
            do {
                // Off-main starting point for the expensive capture — same
                // reasoning as the `createGameData(for:)` dispatcher above,
                // including cancellation propagation into the detached task.
                // See CODE_AUDIT_Game §3.5, CODE_AUDIT_9 §3.1.
                full = try await detachedGameData {
                    try await mapControllable.createMapGameData(for: itemId)
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // Map package export has its own bounded stability check. If
                // an edit crosses that capture window, retry the whole bundle
                // so the player's coalesced repair is not silently dropped.
                continue
            }
            let content = await root.mapRoot.mapGameControllable.networkMapContentUpdate(
                for: itemId
            )
            let state = root.mapRoot.mapGameControllable.networkMapUpdate(for: itemId)
            guard full.id == itemId,
                  content.id == itemId,
                  state.id == itemId,
                  full.assetVersion == content.assetVersion,
                  full.assetVersion == state.assetVersion,
                  full.contentVersion == content.contentVersion,
                  full.contentVersion == state.contentVersion
            else { continue }

            return MapRecoveryBundle(full: full, content: content, state: state)
        }
        throw MapRecoveryError.generationChanged
    }

    /// Nil fingerprints are legacy requests and remain compatible. Current
    /// peers provide both values, which must match the captured response.
    private func mapGeneration(
        of response: NetworkCodableDataType,
        matches request: NetworkCodableDataType
    ) -> Bool {
        if let requestedAssetVersion = request.assetVersion,
           response.assetVersion != requestedAssetVersion {
            return false
        }
        if let requestedContentVersion = request.contentVersion,
           response.contentVersion != requestedContentVersion {
            return false
        }
        return true
    }

    /// The requested generation no longer exists. On a direct master, publish
    /// the newly captured generation as a fresh intent. A direct LAN connection
    /// keeps this physical transfer requester-only; SharePlay broadcasts the
    /// rare supersession so every participant advances consistently.
    private func sendFreshMapRecovery(
        _ recovery: MapRecoveryBundle,
        origin: GameMessageOrigin?
    ) async {
        // A changed generation is a new group intent for SharePlay. A direct LAN
        // requester can receive it on its exact connection without duplicating a
        // multi-part repair to every LAN peer.
        let deliveryOrigin: GameMessageOrigin? = if let origin, case .direct = origin {
            origin
        } else {
            nil
        }
        await send(
            type: .reveal,
            subtype: .show,
            updated: recovery.full,
            origin: deliveryOrigin,
            authoritativeMaster: true
        )
        await send(
            type: .update,
            subtype: .generic,
            updated: recovery.content,
            origin: deliveryOrigin,
            authoritativeMaster: true
        )
        await send(
            type: .update,
            subtype: .mapState,
            updated: recovery.state,
            origin: deliveryOrigin,
            authoritativeMaster: true
        )
    }
}
