// @copyright André Trettin

#if os(iOS) || os(macOS) || os(visionOS)
import CoreRPG
import Foundation
import MapRPG
import RealityKit
import SwiftUI

extension GameTableModel {
    // MARK: - Pin Photo Popover

    /// A double tap on a pin opens or closes its photo popover. A player's stays on this device:
    /// the presentation is not map state, so nothing is mutated or broadcast, and players see
    /// the photos of the pins that are on the map for them. The game master's is shown to
    /// everyone: the map state carries the flag, set on this pin and cleared on all others, and
    /// the players merge it. A hidden pin's photo stays on the game master's device.
    func pinDoubleTapped(pinId: UUID) {
        guard let mapModel = currentMapModel(),
              pinId != mapModel.pointer.id,
              let pin = mapModel.mapPins.first(where: { $0.id == pinId }),
              setup.pinPawns.contains(where: { $0.pinId == pinId }),
              let tap = MapPinPhotoSharing.doubleTap(
                  on: pin,
                  isGameMaster: isGameMaster,
                  isPopoverOpen: photoPinId == pinId,
                  isVisibleToPlayers: mapModel.isPinVisibleToPlayers(pin)
              ) else { return }
        if let shared = tap.sharedFlag {
            setSharedPinPhoto(pinId: pinId, shown: shared)
        }
        // Read again: the sync above may have changed the pin's state.
        let current = currentMapModel()?.mapPins.first(where: { $0.id == pinId }) ?? pin
        setPinPhoto(tap.showsPopover ? current : nil)
    }

    /// Sets the shared photo flag of one pin (clearing it on all others when showing) and
    /// broadcasts the map state. The sync applies the change to the popover, like on every
    /// other device.
    private func setSharedPinPhoto(pinId: UUID, shown: Bool) {
        guard isGameMaster, let mapId = currentMapId,
              mapRoot.mapGameControllable.setPinPhotoShown(itemId: mapId, pinId: pinId, shown: shown) else { return }
        syncPawnsWithMapPins()
        broadcastMapEdit(for: mapId)
    }

    /// Opens the photo popover on `pin`, or closes it with `nil`. Opening it closes the pin's
    /// action menu, which would stand on the same spot.
    func setPinPhoto(_ pin: MapPinModel?) {
        guard photoPinId != pin?.id else {
            photoPin = pin
            return
        }
        photoPinId = pin?.id
        photoPin = pin
        if let pin, selectedPinId == pin.id {
            clearPinSelection()
        }
        updateAttachmentPosition(for: .pinPhoto)
#if !os(visionOS)
        if pin == nil {
            clearPopoverSource(for: .pinPhoto)
        }
#endif
    }

    func clearPinPhoto() {
        setPinPhoto(nil)
    }

    /// The user closed the photo popover (Escape). When the game master closes a photo they have
    /// shown to the players, it closes for everyone: the shared flag is turned off and broadcast.
    func dismissPinPhoto() {
        guard let pinId = photoPinId else { return }
        clearPinPhoto()
        guard MapPinPhotoSharing.dismissEndsSharing(
            of: currentMapModel()?.mapPins.first(where: { $0.id == pinId }),
            isGameMaster: isGameMaster
        ) else { return }
        setSharedPinPhoto(pinId: pinId, shown: false)
    }

    /// The pin photo popover's Full Screen button, `nil` outside a game.
    var pinPhotoFullScreenAction: (@MainActor () -> Void)? {
        guard mapRoot.photoPopover.actions != nil else { return nil }
        return { [weak self] in self?.showPinPhotoFullScreen() }
    }

    /// The popover's Full Screen button: closes the popover (for everyone when the game master
    /// shows it) and opens the photo full screen, for every player when the game master shows a
    /// pin they see.
    func showPinPhotoFullScreen() {
        guard let pin = photoPin, let mapId = currentMapId else { return }
        let isShared = isGameMaster && mapRoot.mayShareFullScreenPhoto(of: pin, on: mapId)
        dismissPinPhoto()
        mapRoot.viewController.showPinPhotoFullScreen(root: mapRoot, pin: pin, mapId: mapId, isShared: isShared)
    }

    /// Follows the map after a sync: applies a change of a pin's shared photo flag, and closes
    /// the popover of a pin that is gone or, for a player, hidden. Refreshes the pin's state
    /// for the popover.
    func updatePinPhotoState(mapModel: MapModel?) {
        let pins = mapModel?.mapPins ?? []
        var sharedNow = Set<UUID>()
        for pin in pins where pin.isPhotoShared {
            sharedNow.insert(pin.id)
        }
        let previouslyShared = sharedPhotoPinIds
        sharedPhotoPinIds = sharedNow

        for pin in pins {
            switch MapPinPhotoSharing.change(
                wasShared: previouslyShared.contains(pin.id),
                isShared: sharedNow.contains(pin.id)
            ) {
            case .show:
                if isGameMaster || pin.isShown {
                    setPinPhoto(pin)
                }
            case .hide:
                if photoPinId == pin.id {
                    clearPinPhoto()
                }
            case nil:
                break
            }
        }

        guard let photoPinId else { return }
        guard let pin = pins.first(where: { $0.id == photoPinId }),
              isGameMaster || pin.isShown,
              setup.pinPawns.contains(where: { $0.pinId == photoPinId }) else {
            clearPinPhoto()
            return
        }
        photoPin = pin
        updateAttachmentPosition(for: .pinPhoto)
    }
}

#endif
