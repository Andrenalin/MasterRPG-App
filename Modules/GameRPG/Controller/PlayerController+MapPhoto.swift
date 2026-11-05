// @copyright André Trettin

import CoreRPG
import Foundation
import MapRPG
import os.log
import PhotoRPG

// A photo the game master shows while a map is on screen: on the map in the pin photo popover,
// full screen, or closed. The game master's `.update/.photoPresentation` names the photo, the
// map, the anchor and the mode before the photo's reveal. Every viewer can switch the mode on
// their own device; each change of the game master goes to everyone and wins.
//
// | Mode       | `gameUpdateType` | `MapPhotoPopoverModel.photo` |
// |------------|------------------|------------------------------|
// | popover    | `.map`           | set                          |
// | fullScreen | `.photo`         | nil                          |
// | closed     | `.map`           | nil                          |

extension PlayerController {
    /// Installs what the photo popovers' buttons do for the length of this game.
    func installMapPhotoActions() {
        root.mapRoot.photoPopover.actions = MapPhotoPopoverActions(
            showFullScreen: { [weak self] in self?.requestMapPhotoMode(.fullScreen) },
            close: { [weak self] in self?.requestMapPhotoMode(.closed) },
            showPhotoFullScreen: { [weak self] photo, isShared in
                self?.showPhotoFullScreen(photo, isShared: isShared)
            }
        )
    }

    /// Removes the popover and its actions when the game ends.
    func uninstallMapPhotoActions() {
        root.mapRoot.photoPopover.actions = nil
        root.mapRoot.photoPopover.photo = nil
        gameModel.mapPhoto.reset()
    }

    /// The game master's `.update/.photoPresentation`. Applied at once when this device holds
    /// the photo; a photo it does not hold yet waits for its reveal (see `presentPhoto(itemId:)`).
    func handleMapPhotoPresentation(_ model: GameNetworkModel) async {
        guard let presentation = MapPhotoPresentation.decodeData(of: model.data.data),
              presentation.photoId == model.data.id
        else {
            Logger.networking.error("PlayerController: Invalid map photo presentation \(model.data.id, privacy: .public)")
            return
        }
        guard gameModel.mapPhoto.applyMaster(presentation) else { return }
        if presentation.mode != .closed, !isCurrentPhoto(presentation.photoId) {
            guard await root.photoRoot.gameControllable.setCurrent(itemId: presentation.photoId),
                  gameModel.mapPhoto.presentation == presentation
            else { return }
        }
        applyMapPhotoMode()
    }

    /// A pin's photo goes full screen from its popover. Shared by the game master for a pin the
    /// players see: then everyone follows. Otherwise it stays on this device.
    func showPhotoFullScreen(_ photo: MapPhotoPopoverItem, isShared: Bool) {
        if isShared, gameModel.asGameMaster, let masterController = root.gameModel.masterController {
            let presentation = MapPhotoPresentation(
                photoId: photo.photoId,
                mapId: photo.mapId,
                anchor: photo.anchor,
                title: photo.title,
                mode: .fullScreen,
                sequence: masterController.gameModel.nextMapPhotoSequence(),
                sessionId: masterController.gameModel.deliverySessionID
            )
            gameModel.mapPhoto.applyMaster(presentation)
            applyMapPhotoMode()
            root.scheduleMapPhotoBroadcast(presentation)
        } else {
            gameModel.mapPhoto.presentLocal(MapPhotoPresentation(
                photoId: photo.photoId,
                mapId: photo.mapId,
                anchor: photo.anchor,
                title: photo.title,
                mode: .fullScreen,
                sequence: 0,
                sessionId: UUID()
            ))
            applyMapPhotoMode()
        }
    }

    /// A viewer's change from the popover or the full-screen controls. On the game master's
    /// device it goes to every player, unless the photo is one only the game master sees; on a
    /// player's or observer's device it stays local.
    func requestMapPhotoMode(_ mode: MapPhotoMode) {
        let state = gameModel.mapPhoto
        guard let presentation = state.presentation else { return }
        if gameModel.asGameMaster, !state.isLocal, let masterController = root.gameModel.masterController {
            let changed = presentation.changed(
                to: mode,
                sequence: masterController.gameModel.nextMapPhotoSequence()
            )
            // The broadcast comes back to this device with the same sequence and is ignored.
            gameModel.mapPhoto.applyMaster(changed)
            applyMapPhotoMode()
            root.scheduleMapPhotoBroadcast(changed)
        } else {
            guard gameModel.mapPhoto.setLocal(mode) else { return }
            applyMapPhotoMode()
        }
    }

    /// Shows the current mode: switches the game screen and sets or clears the map popover.
    func applyMapPhotoMode() {
        let state = gameModel.mapPhoto
        guard let presentation = state.presentation else {
            root.mapRoot.photoPopover.photo = nil
            return
        }
        switch state.mode {
        case .popover:
            gameModel.setGameUpdateType(.map)
            root.mapRoot.photoPopover.photo = MapPhotoPopoverItem(
                photoId: presentation.photoId,
                mapId: presentation.mapId,
                anchor: presentation.anchor,
                title: presentation.title
            )
        case .fullScreen:
            root.mapRoot.photoPopover.photo = nil
            if isCurrentPhoto(presentation.photoId) {
                showFullScreen(photoId: presentation.photoId)
            } else {
                // The full-screen viewer shows the photo module's current photo: a pin's photo
                // becomes current first.
                Task { [weak self] in
                    guard let self,
                          await root.photoRoot.gameControllable.setCurrent(itemId: presentation.photoId),
                          gameModel.mapPhoto.presentation == presentation,
                          gameModel.mapPhoto.mode == .fullScreen
                    else { return }
                    showFullScreen(photoId: presentation.photoId)
                }
            }
        case .closed:
            root.mapRoot.photoPopover.photo = nil
            gameModel.setGameUpdateType(.map)
        }
    }

    private func showFullScreen(photoId: UUID) {
        gameModel.setGameUpdateType(.photo)
        root.photoRoot.photoGameControllable.presentPhoto(itemId: photoId)
    }

    /// A photo revealed while its presentation waits shows the way the game master chose, as
    /// long as the map it belongs to is loaded. Returns `false` when there is none, and the
    /// photo is shown full screen as before.
    func presentPhotoOnMap(itemId: UUID) -> Bool {
        guard let presentation = gameModel.mapPhoto.pending(for: itemId),
              root.mapRoot.gameControllable.gameModel.currentItemId == presentation.mapId
        else {
            clearMapPhoto()
            return false
        }
        applyMapPhotoMode()
        return true
    }

    /// Showing anything else closes the photo on the map: another module's item or a map, also
    /// the same one again. Only a live map state of its map keeps it.
    func noteMasterPresentation(type: RPGMessageType, module: NetworkModules, itemId: UUID) {
        guard let presentation = gameModel.mapPhoto.presentation else { return }
        switch module {
        case .photo:
            return
        case .map where type == .update && itemId == presentation.mapId:
            return
        default:
            clearMapPhoto()
        }
    }

    private func clearMapPhoto() {
        guard gameModel.mapPhoto.presentation != nil else { return }
        gameModel.mapPhoto.clear()
        root.mapRoot.photoPopover.photo = nil
    }

    private func isCurrentPhoto(_ photoId: UUID) -> Bool {
        root.photoRoot.gameControllable.gameModel.currentItemId == photoId
    }
}
