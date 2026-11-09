// @copyright André Trettin

import CoreRPG
import Foundation
import MapRPG

// The game master's "Clear Map": the map leaves every screen, the game master's own included.
// There is no message of its own for it. It is a `.reveal/.show` of module `.none`, which a
// player orders with the other shows (`GameNetworkModel.isPresentation`) and which leaves no
// package to build or to replay: a player that joins later is replayed nothing, as before any
// show. See `PlayerController+ClearMap.swift` for the receiving side.

extension MasterController {
    /// Takes the shown map off the screens. With `shareWithPlayers` the clear goes to everyone
    /// and reaches the game master's own player through its loopback; without it (sharing is
    /// paused) only the game master's own screen is cleared, as for every other edit.
    func clearShownMap(shareWithPlayers: Bool) async {
        guard !asProxy else { return }
        // A pin photo shared earlier is over with the map, as when another map is shown.
        root.mapRoot.mapGameControllable.clearSharedPinPhotos()
        guard shareWithPlayers else {
            root.gameModel.playerController?.clearShownMap()
            return
        }
        let mapId = root.mapRoot.gameControllable.gameModel.currentItemId ?? UUID()
        let reference = NetworkCodableDataType(id: mapId, type: .none, version: 0)
        let message = outgoingMessage(type: .reveal, subtype: .show, updated: reference)
        // A show whose package is still being built is over now.
        gameModel.latestShownCounter = message.counter
        await root.statisticsModel.record(message, direction: .outgoing, origin: .direct(nil))
        await store.sendPlayer(data: message)
    }
}
