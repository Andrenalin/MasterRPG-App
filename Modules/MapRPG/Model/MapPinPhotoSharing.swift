// @copyright André Trettin

import Foundation

/// What a change of a pin's shared photo flag means for the popover on this device.
public enum MapPinPhotoSharing {
    public enum Change: Equatable, Sendable {
        /// The game master started showing the photo: open the popover.
        case show
        /// The game master stopped showing it: close the popover.
        case hide
    }

    /// The reaction to a pin's shared flag going from `wasShared` to `isShared`, `nil` when it
    /// did not change. Only a change counts, so a pin that is already shared when a map opens
    /// (a stale flag from an earlier session) does not pop up by itself.
    public static func change(wasShared: Bool, isShared: Bool) -> Change? {
        guard wasShared != isShared else { return nil }
        return isShared ? .show : .hide
    }
}

// MARK: - Interaction rules

/// The rules of the pin photo that the 2D map and the 3D table both apply. The surfaces only
/// read the answer and carry it out (open the popover, set the shared flag), so a fix lands once.
/// See CODE_AUDIT_24 §9.4.
public extension MapPinPhotoSharing {
    /// What a double tap on a pin does.
    struct DoubleTap: Equatable, Sendable {
        /// Open the pin's photo popover on this device (`false`: close it).
        public let showsPopover: Bool
        /// The shared flag to set on the pin (and clear on every other one), or `nil` to leave it.
        /// The game master's popover goes to everyone only while the pin is visible to the
        /// players; a hidden pin's photo stays on the game master's device.
        public let sharedFlag: Bool?
    }

    /// The reaction to a double tap on `pin`, or `nil` when the pin has no photo popover for this
    /// viewer: a player only sees the photos of pins that are on the map for them.
    /// - Parameters:
    ///   - isPopoverOpen: this pin's popover is open on this device now.
    ///   - isVisibleToPlayers: `MapModel.isPinVisibleToPlayers` for the pin.
    static func doubleTap(
        on pin: MapPinModel,
        isGameMaster: Bool,
        isPopoverOpen: Bool,
        isVisibleToPlayers: Bool
    ) -> DoubleTap? {
        guard isGameMaster || pin.isShown else { return nil }
        let show = !isPopoverOpen
        let shares = isGameMaster && (pin.isShown || pin.isPhotoShared)
        return DoubleTap(
            showsPopover: show,
            sharedFlag: shares ? show && isVisibleToPlayers : nil
        )
    }

    /// Whether closing the popover of `pin` also ends the photo for everyone: the game master
    /// closes a photo they have shown.
    static func dismissEndsSharing(of pin: MapPinModel?, isGameMaster: Bool) -> Bool {
        isGameMaster && pin?.isPhotoShared == true
    }
}
