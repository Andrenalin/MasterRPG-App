// @copyright André Trettin

import CoreRPG
import Foundation
import MapRPG
import PhotoRPG

// A photo shown while the map is on the game master's screen opens on the map, pointing at the
// room the game master opened last. The game master's `.update/.photoPresentation` goes out
// before the photo's reveal, so a player knows how to show the photo when it arrives. See
// `PlayerController+MapPhoto.swift` for the receiving side.

extension MasterController {
    /// The presentation for a photo about to be shown, `nil` when the map is not on the game
    /// master's screen and the photo is shown full screen as before.
    func newMapPhotoPresentation(for photoId: UUID) -> MapPhotoPresentation? {
        guard !asProxy,
              let screen = root.gameModel.playerController?.gameModel,
              let mapId = root.mapRoot.gameControllable.gameModel.currentItemId
        else { return nil }
        let isMapShown = switch screen.gameUpdateType {
        case .map:
            true
        case .photo:
            // A photo of the map is full screen: the next one opens on the map again.
            screen.mapPhoto.presentation?.mapId == mapId
        default:
            false
        }
        guard isMapShown else { return nil }
        return MapPhotoPresentation(
            photoId: photoId,
            mapId: mapId,
            anchor: root.mapRoot.mapGameControllable.photoAnchor(for: mapId),
            mode: .popover,
            sequence: gameModel.nextMapPhotoSequence(),
            sessionId: gameModel.deliverySessionID
        )
    }

    /// Sends the game master's presentation of a photo over the map to every player.
    func broadcastMapPhoto(_ presentation: MapPhotoPresentation) async {
        await send(type: .update, subtype: .photoPresentation, updated: presentation.networkData)
    }

    /// Replays a photo shown over the map to a peer that just became ready: the map, its live
    /// state, the presentation and then the photo. Returns `false` when no photo is shown over
    /// the map, and the regular replay runs.
    func replayMapPhoto(to origin: GameMessageOrigin) async -> Bool {
        guard !asProxy,
              let state = root.gameModel.playerController?.gameModel.mapPhoto,
              state.isActive,
              !state.isLocal,
              let presentation = state.presentation,
              root.mapRoot.gameControllable.gameModel.currentItemId == presentation.mapId
        else { return false }

        let map = await root.mapRoot.mapGameControllable.shareMap(id: presentation.mapId)
        await send(type: .reveal, subtype: .show, updated: map.reference, origin: origin, authoritativeMaster: true)
        await sendMapFollowUps(for: presentation.mapId, origin: origin)
        await send(
            type: .update,
            subtype: .photoPresentation,
            updated: presentation.networkData,
            origin: origin,
            authoritativeMaster: true
        )
        let photo = await root.photoRoot.gameControllable.share(id: presentation.photoId)
        await send(type: .reveal, subtype: .show, updated: photo.reference, origin: origin, authoritativeMaster: true)
        return true
    }
}
