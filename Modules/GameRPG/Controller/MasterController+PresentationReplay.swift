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

// MARK: - Presentation Replay

extension MasterController {
    /// Not `private` because `MasterController+NetworkStoreDelegate.swift`'s
    /// `ready(for:)` and `MasterController+ProxyDelegate.swift`'s
    /// `readyProxy(for:)` both call this directly, from two different files.
    func replayCurrentPresentation(to origin: GameMessageOrigin) async {
        guard let presentation = root.gameModel.playerController?.gameModel.gameUpdateType else { return }

        let reference: NetworkCodableDataType?
        switch presentation {
        case .map:
            reference = if let id = root.mapRoot.gameControllable.gameModel.currentItemId {
                await root.mapRoot.mapGameControllable.shareMap(id: id)
            } else {
                nil
            }
        case .pdf:
            reference = if let id = root.pdfRoot.gameControllable.gameModel.currentItemId {
                await root.pdfRoot.gameControllable.share(id: id)
            } else {
                nil
            }
        case .photo:
            reference = if let id = root.photoRoot.gameControllable.gameModel.currentItemId {
                await root.photoRoot.gameControllable.share(id: id)
            } else {
                nil
            }
        case .table:
            // Tables are Messenger-only. Without a SharePlay replay, a late
            // participant could finish Journal synchronization by showing an
            // older Photo/Map even though the current screen is a Table. Keep
            // the existing LAN/proxy reconnect policy, but send the master's
            // canonical Table reference to the newly active SharePlay peer.
            reference = if case .sharePlay = origin,
                           let id = root.tableRoot.gameControllable.gameModel.currentItemId {
                await root.tableRoot.gameControllable.share(id: id)
            } else {
                nil
            }
        case .value:
            // Values are not presentations. A proxy receives the host's full
            // Character through readyProxy(for:) immediately below instead.
            reference = nil
        case .weather:
            reference = if let id = root.weatherRoot.gameControllable.gameModel.currentItemId {
                await root.weatherRoot.weatherGameControllable.shareWeather(id: id)
            } else {
                nil
            }
        case .space:
            reference = if let id = root.spaceRoot.gameControllable.gameModel.currentItemId {
                await root.spaceRoot.gameControllable.share(id: id)
            } else {
                nil
            }
        default:
            reference = nil
        }

        guard let reference else { return }
        let replayReference = Self.presentationReplayReference(reference, origin: origin)
        await send(
            type: .reveal,
            subtype: .show,
            updated: replayReference,
            origin: origin,
            authoritativeMaster: true
        )
        if presentation == .map {
            // A paused "Share Map" keeps the live map state private. See CODE_AUDIT_20 §5.2.
            guard mayShareMapState(for: reference.id) else { return }
            let mapUpdate = await root.mapRoot.mapGameControllable.networkMapContentUpdate(for: reference.id)
            await send(
                type: .update,
                subtype: .generic,
                updated: mapUpdate,
                origin: origin,
                authoritativeMaster: true
            )
            let mapState = root.mapRoot.mapGameControllable.networkMapUpdate(for: reference.id)
            await send(
                type: .update,
                subtype: .mapState,
                updated: mapState,
                origin: origin,
                authoritativeMaster: true
            )
        } else if presentation == .space,
                  let transformReplay = root.spaceRoot.spaceGameControllable.latestSpaceTransformReplay(
                      for: reference.id,
                      version: reference.effectiveAssetVersion
                  ) {
            // Messenger transforms have no history. Replay the retained pose
            // after the asset reference; the Space viewer also retains it while
            // the file-backed entity is still loading.
            await send(
                type: .update,
                subtype: .spaceTransform,
                updated: transformReplay.data,
                timestamp: transformReplay.timestamp,
                appliesLocalSpaceTransform: false,
                origin: origin,
                authoritativeMaster: true
            )
        }
    }
}

extension MasterController {
    /// A late SharePlay participant already receives the current Journal
    /// snapshot. Replay only Weather's canonical identity over Messenger so the
    /// replay is physically targeted and cannot replace the session-wide
    /// Journal attachment. If that participant missed the bytes, its normal
    /// availability check requests the full package from the master.
    static func presentationReplayReference(
        _ reference: NetworkCodableDataType,
        origin: GameMessageOrigin
    ) -> NetworkCodableDataType {
        guard case .sharePlay = origin,
              reference.type == .weather,
              reference.data != nil
        else { return reference }

        return NetworkCodableDataType(
            id: reference.id,
            type: reference.type,
            version: reference.version,
            assetVersion: reference.assetVersion,
            contentVersion: reference.contentVersion
        )
    }
}
