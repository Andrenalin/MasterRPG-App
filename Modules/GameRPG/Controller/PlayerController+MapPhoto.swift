// @copyright André Trettin

import CoreRPG
import Foundation
import os.log
import AdventureRPG
import AudioRPG
import CharacterRPG
import DiceRPG
import MapRPG
import PdfRPG
import PhotoRPG
import SpaceRPG
import TableRPG
import WeatherRPG

// A photo or a weather the game master shows while a map is on screen: on the map in the pin
// photo popover, full screen, or closed. The game master's `.update/.photoPresentation` names the
// item, the map, the anchor and the mode before the item's reveal. Every viewer can switch the
// mode on their own device; each change of the game master goes to everyone and wins.
//
// | Mode       | `gameUpdateType` | `MapPhotoPopoverModel.photo` |
// |------------|------------------|------------------------------|
// | popover    | `.map`           | set                          |
// | fullScreen | `.photo`/`.weather` | nil                        |
// | closed     | `.map`           | nil                          |

extension PlayerController {
    /// Installs what the photo popovers' buttons do for the length of this game.
    func installMapPhotoActions() {
        let popover = root.mapRoot.photoPopover
        popover.actions = MapPhotoPopoverActions(
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
        cancelMapPhotoMakeCurrent()
        gameModel.mapPhoto.reset()
        // The table's weather ends with the game, too.
        gameModel.tableWeather.reset()
    }

    /// The game master's `.update/.photoPresentation`, for a photo or a weather. Applied at once
    /// when this device holds the item; one it does not hold yet waits for its reveal (see
    /// `presentOnMap(_:itemId:)`).
    func handleMapPhotoPresentation(_ model: GameNetworkModel) async {
        guard let presentation = MapPhotoPresentation.decodeData(of: model.data.data),
              presentation.itemId == model.data.id,
              presentation.module == model.data.type,
              Self.mapItemModules.contains(presentation.module)
        else {
            Logger.networking.error("PlayerController: Invalid map photo presentation \(model.data.id, privacy: .public)")
            return
        }
        guard gameModel.mapPhoto.applyMaster(presentation) else { return }
        if presentation.mode != .closed, !isCurrent(presentation) {
            guard await makeCurrent(presentation),
                  gameModel.mapPhoto.presentation == presentation
            else { return }
        }
        applyMapPhotoMode()
    }

    /// A pin's photo goes full screen from its popover. Shared by the game master for a pin the
    /// players see: then everyone follows. Otherwise it stays on this device.
    func showPhotoFullScreen(_ photo: MapPhotoPopoverItem, isShared: Bool) {
        // Also a backstop for every caller: nothing goes out while "Share Map" is paused.
        // See CODE_AUDIT_24 §6.2.
        if isShared, gameModel.asGameMaster, root.mapRoot.rootModel.isMapStreaming,
           let masterController = root.gameModel.masterController {
            let presentation = MapPhotoPresentation(
                itemId: photo.itemId,
                module: photo.module,
                mapId: photo.mapId,
                anchor: photo.anchor,
                title: photo.title,
                mode: .fullScreen,
                sequence: masterController.gameModel.nextMapPhotoSequence(),
                sessionId: masterController.gameModel.deliverySessionId
            )
            gameModel.mapPhoto.applyMaster(presentation)
            applyMapPhotoMode()
            root.scheduleMapPhotoBroadcast(presentation)
        } else {
            gameModel.mapPhoto.presentLocal(MapPhotoPresentation(
                itemId: photo.itemId,
                module: photo.module,
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
    /// device it goes to every player, unless the item is one only the game master sees; on a
    /// player's or observer's device it stays local.
    func requestMapPhotoMode(_ mode: MapPhotoMode) {
        let state = gameModel.mapPhoto
        guard let presentation = state.presentation else {
            // Nothing is presented, so a popover still on screen is stale: Close removes it.
            applyMapPhotoMode()
            return
        }
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
            cancelMapPhotoMakeCurrent()
            gameModel.setGameUpdateType(.map)
            root.mapRoot.photoPopover.isPrivate = state.isLocal
            root.mapRoot.photoPopover.photo = MapPhotoPopoverItem(
                itemId: presentation.itemId,
                module: presentation.module,
                mapId: presentation.mapId,
                anchor: presentation.anchor,
                title: presentation.title
            )
        case .fullScreen:
            root.mapRoot.photoPopover.photo = nil
            cancelMapPhotoMakeCurrent()
            if isCurrent(presentation) {
                showFullScreen(presentation)
            } else {
                // The full-screen viewer shows its module's current item: a pin's photo
                // becomes current first. Only the newest presentation may do that, or an older
                // fetch that finishes last would leave its item in front.
                gameModel.mapPhotoMakeCurrentTask = Task { [weak self] in
                    guard let self,
                          await makeCurrent(presentation),
                          !Task.isCancelled,
                          gameModel.mapPhoto.presentation == presentation,
                          gameModel.mapPhoto.mode == .fullScreen
                    else { return }
                    showFullScreen(presentation)
                }
            }
        case .closed:
            cancelMapPhotoMakeCurrent()
            root.mapRoot.photoPopover.photo = nil
            gameModel.setGameUpdateType(.map)
        }
    }

    func cancelMapPhotoMakeCurrent() {
        gameModel.mapPhotoMakeCurrentTask?.cancel()
        gameModel.mapPhotoMakeCurrentTask = nil
    }

    private func showFullScreen(_ presentation: MapPhotoPresentation) {
        if presentation.module == .weather {
            gameModel.showWeather()
        } else {
            gameModel.setGameUpdateType(presentation.module)
            root.photoRoot.photoGameControllable.presentPhoto(itemId: presentation.itemId)
            // After the photo is current: visionOS opens its photo window on this.
            gameModel.mapPhoto.noteFullScreenShown()
        }
    }

    /// A photo that arrives while the game master's full-screen presentation of it waits (the
    /// player did not hold it when the presentation came) is shown now.
    func applyWaitingMapPhoto(itemId: UUID) {
        let state = gameModel.mapPhoto
        guard state.mode == .fullScreen,
              let presentation = state.presentation,
              presentation.module == .photo,
              presentation.itemId == itemId,
              gameModel.gameUpdateType != .photo || !isCurrent(presentation)
        else { return }
        applyMapPhotoMode()
    }

    /// An item revealed while its presentation waits shows the way the game master chose, as
    /// long as the map it belongs to is loaded. Returns `false` when there is none, and the
    /// item is shown full screen as before.
    func presentOnMap(_ module: NetworkModules, itemId: UUID) -> Bool {
        guard let presentation = gameModel.mapPhoto.pending(for: module, itemId: itemId),
              root.mapRoot.gameControllable.gameModel.currentItemId == presentation.mapId
        else {
            clearMapPhoto()
            return false
        }
        applyMapPhotoMode()
        return true
    }

    /// Showing anything else closes the item on the map: another module's item or a map, also
    /// the same map again. A live map state of its map keeps it. A photo or a weather decides on
    /// its reveal: `presentOnMap(_:itemId:)` keeps the presentation waiting for it and closes any
    /// other.
    func noteMasterPresentation(type: RPGMessageType, module: NetworkModules, itemId: UUID) {
        guard let presentation = gameModel.mapPhoto.presentation else { return }
        if Self.mapItemModules.contains(module) {
            return
        }
        if module == .map, type == .update, itemId == presentation.mapId {
            return
        }
        clearMapPhoto()
    }

    /// The modules a presentation over the map can show.
    static let mapItemModules: Set<NetworkModules> = [.photo, .weather]

    private func clearMapPhoto() {
        guard gameModel.mapPhoto.presentation != nil else { return }
        gameModel.mapPhoto.clear()
        root.mapRoot.photoPopover.photo = nil
    }

    private func gameControllable(for module: NetworkModules) -> any GameControllable {
        module == .weather ? root.weatherRoot.gameControllable : root.photoRoot.gameControllable
    }

    private func isCurrent(_ presentation: MapPhotoPresentation) -> Bool {
        gameControllable(for: presentation.module).gameModel.currentItemId == presentation.itemId
    }

    private func makeCurrent(_ presentation: MapPhotoPresentation) async -> Bool {
        await gameControllable(for: presentation.module).setCurrent(itemId: presentation.itemId)
    }
}
