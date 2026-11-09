// @copyright André Trettin

import CoreRPG
import Foundation
import MapRPG

// The game master's "Clear Map" as a player receives it: a `.reveal/.show` of module `.none`.
// See `MasterController+ClearMap.swift` for the sending side.

extension PlayerController {
    /// The `.reveal/.show` of module `.none`. Any other message of that module has nothing to
    /// show and is ignored, as before. Nothing is answered: no package is owed.
    func handleMapCleared(_ model: GameNetworkModel) -> GameNetworkModel? {
        guard model.sender.isMaster, model.type == .reveal, model.subType == .show else { return nil }
        clearShownMap()
        return nil
    }

    /// Takes the map off this device's screens: the map is no longer current (its game copy and
    /// session state stay for a later show), a photo over it is closed, and the idle screen
    /// returns. Also used directly by the game master's device when sharing is paused.
    func clearShownMap() {
        root.mapRoot.gameControllable.gameModel.clearCurrent()
        root.mapRoot.photoPopover.photo = nil
        gameModel.mapPhoto.clear()
        cancelMapPhotoMakeCurrent()
        if gameModel.gameUpdateType == .map {
            gameModel.setGameUpdateType(.none)
        }
    }
}
