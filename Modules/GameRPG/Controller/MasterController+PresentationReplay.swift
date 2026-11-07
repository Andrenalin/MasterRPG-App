// @copyright André Trettin

import CoreRPG
import Foundation
import MapRPG
import PdfRPG
import PhotoRPG
import SpaceRPG
import TableRPG
import WeatherRPG

// MARK: - Presentation Replay

extension MasterController {
    /// Not `private` because `MasterController+NetworkStoreDelegate.swift`'s
    /// `ready(for:)` and `MasterController+ProxyDelegate.swift`'s
    /// `readyProxy(for:)` both call this directly, from two different files.
    func replayCurrentPresentation(to origin: GameMessageOrigin) async {
        // `sharedUpdateType`, not `gameUpdateType`: a photo the game master opened privately from
        // a hidden pin must not be replayed to a joining or reconnecting player.
        guard let presentation = root.gameModel.playerController?.gameModel.sharedUpdateType else { return }
        // First, so a weather revealed below is already held and needs no request.
        await replayTableWeather(to: origin)
        // A photo over the map needs the map, the photo and how it is shown.
        guard await !replayMapPhoto(to: origin) else { return }

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
        // Messenger has no history: the newly ready participant gets the reference of the
        // current presentation and asks for the bytes if it lacks them.
        await send(
            type: .reveal,
            subtype: .show,
            updated: reference.reference,
            origin: origin,
            authoritativeMaster: true
        )
        if presentation == .map {
            await sendMapFollowUps(for: reference.id, origin: origin)
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
