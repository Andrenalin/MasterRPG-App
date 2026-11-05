// @copyright André Trettin

import CoreRPG
import Foundation
import MapRPG
import PhotoRPG
import WeatherRPG

// A photo or a weather shown while the map is on the game master's screen opens on the map,
// pointing at the room the game master opened last. The game master's `.update/.photoPresentation`
// goes out before the item's reveal, so a player knows how to show the item when it arrives. See
// `PlayerController+MapPhoto.swift` for the receiving side.

extension MasterController {
    /// The presentation for a photo or a weather about to be shown, `nil` when the map is not on
    /// the game master's screen and the item is shown full screen as before.
    func newMapPhotoPresentation(for module: NetworkModules, itemId: UUID) -> MapPhotoPresentation? {
        guard !asProxy,
              PlayerController.mapItemModules.contains(module),
              let screen = root.gameModel.playerController?.gameModel,
              let mapId = root.mapRoot.gameControllable.gameModel.currentItemId
        else { return nil }
        // A photo or weather of the map in full screen: the next one opens on the map again.
        let isMapShown = screen.gameUpdateType == .map
            || (screen.mapPhoto.mode == .fullScreen && screen.mapPhoto.presentation?.mapId == mapId)
        guard isMapShown else { return nil }
        return MapPhotoPresentation(
            itemId: itemId,
            module: module,
            mapId: mapId,
            anchor: root.mapRoot.mapGameControllable.photoAnchor(for: mapId),
            title: module == .weather ? weatherTitle(for: itemId) : nil,
            mode: .popover,
            sequence: gameModel.nextMapPhotoSequence(),
            sessionId: gameModel.deliverySessionID
        )
    }

    /// Sends the game master's presentation of a photo or weather over the map to every player.
    func broadcastMapPhoto(_ presentation: MapPhotoPresentation) async {
        await send(type: .update, subtype: .photoPresentation, updated: presentation.networkData)
    }

    /// Replays a photo or weather shown over the map to a peer that just became ready: the map,
    /// its live state, the presentation and then the item. Returns `false` when nothing is shown
    /// over the map, and the regular replay runs.
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
        let item = presentation.module == .weather
            ? await root.weatherRoot.weatherGameControllable.shareWeather(id: presentation.itemId)
            : await root.photoRoot.gameControllable.share(id: presentation.itemId)
        await send(type: .reveal, subtype: .show, updated: item.reference, origin: origin, authoritativeMaster: true)
        return true
    }

    /// A weather's name as the popover's caption; players hold the weather in game memory only.
    private func weatherTitle(for itemId: UUID) -> String? {
        let name = root.weatherRoot.itemControllable.nameSync(itemId: itemId)
        return name.isEmpty ? nil : name
    }
}
