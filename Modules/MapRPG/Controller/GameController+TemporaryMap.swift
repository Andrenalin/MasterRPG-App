// @copyright André Trettin

import CoreRPG
import Foundation
import PhotoRPG

// A map made during the game from a photo. It lives in game memory only: it is never added to
// the library's items, so it is not saved, not part of a saved game, and gone with
// `ItemGameModel.reset()`. The game shows it like any map: the reference names it, players that
// lack it get the package and the local player finds it in game memory.

extension GameController {
    @MainActor
    func createTemporaryMap(photoId: UUID) async -> NetworkCodableDataType? {
        guard itemController.itemDataModel.isGameMode,
              let geometry = await root.photoRoot.fetchPhotoGeometry(for: photoId, useGame: true),
              // The game may have ended while the photo was measured.
              itemController.itemDataModel.isGameMode,
              !Task.isCancelled
        else { return nil }

        let map = MapModel(id: UUID(), name: root.photoRoot.itemControllable.nameSync(itemId: photoId))
        map.resetImage(with: photoId, size: geometry.size, degrees: geometry.degrees)
        gameModel.itemData[map.id] = map
        return await shareMap(id: map.id)
    }
}
