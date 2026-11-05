// @copyright André Trettin

import Foundation
import Observation

/// A photo shown on the game map, in the photo popover.
public struct MapPhotoPopoverItem: Equatable, Sendable {
    public let photoId: UUID
    public let mapId: UUID
    /// Where the popover points, in the map's canvas coordinates.
    public let anchor: CGPoint
    /// The caption, such as a pin's name. `nil` uses the photo's name.
    public let title: String?

    public init(photoId: UUID, mapId: UUID, anchor: CGPoint, title: String? = nil) {
        self.photoId = photoId
        self.mapId = mapId
        self.anchor = anchor
        self.title = title
    }
}

/// What the photo popovers' buttons do. GameRPG decides whether a change stays on this device or
/// goes to every player.
public struct MapPhotoPopoverActions {
    /// The game master's photo over the map goes full screen.
    public let showFullScreen: @MainActor () -> Void
    /// The game master's photo over the map closes.
    public let close: @MainActor () -> Void
    /// A pin's photo goes full screen. `isShared` when the game master shows a pin the players
    /// see: then it goes full screen for everyone.
    public let showPhotoFullScreen: @MainActor (_ photo: MapPhotoPopoverItem, _ isShared: Bool) -> Void

    public init(
        showFullScreen: @escaping @MainActor () -> Void,
        close: @escaping @MainActor () -> Void,
        showPhotoFullScreen: @escaping @MainActor (_ photo: MapPhotoPopoverItem, _ isShared: Bool) -> Void
    ) {
        self.showFullScreen = showFullScreen
        self.close = close
        self.showPhotoFullScreen = showPhotoFullScreen
    }
}

/// The photo shown on the game map: set by GameRPG when a photo arrives while a map is on
/// screen, read by the 2D map's viewport overlay and the 3D table. Also routes a pin photo's
/// Full Screen button to the game.
@MainActor @Observable
public final class MapPhotoPopoverModel {
    /// The photo in the popover, `nil` when none is shown.
    public var photo: MapPhotoPopoverItem?
    /// Installed by GameRPG for the length of a game. Holds no view.
    @ObservationIgnored public var actions: MapPhotoPopoverActions?

    public init() {}

    /// The photo to show on `mapId`, `nil` when the popover belongs to another map.
    public func photo(on mapId: UUID?) -> MapPhotoPopoverItem? {
        guard let photo, photo.mapId == mapId else { return nil }
        return photo
    }

    /// Whether a photo can go full screen: only during a game.
    var canShowFullScreen: Bool {
        actions != nil
    }

    func showFullScreen() {
        actions?.showFullScreen()
    }

    func close() {
        if let actions {
            actions.close()
        } else {
            photo = nil
        }
    }

    /// Shows a pin's photo full screen. The caller closes the pin's popover first.
    func showFullScreen(pin: MapPinModel, mapId: UUID, isShared: Bool) {
        guard let photoId = pin.photoId else { return }
        actions?.showPhotoFullScreen(
            MapPhotoPopoverItem(
                photoId: photoId,
                mapId: mapId,
                anchor: pin.location,
                title: pin.name.isEmpty ? nil : pin.name
            ),
            isShared
        )
    }
}
