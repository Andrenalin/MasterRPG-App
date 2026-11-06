// @copyright André Trettin

import CoreRPG
import Foundation
import Observation
import SwiftUI

/// A photo or a weather shown on the game map, in the photo popover.
public struct MapPhotoPopoverItem: Equatable, Sendable {
    /// The photo's or the weather's id.
    public let itemId: UUID
    /// `.photo` or `.weather`.
    public let module: NetworkModules
    public let mapId: UUID
    /// Where the popover points, in the map's canvas coordinates.
    public let anchor: CGPoint
    /// The caption, such as a pin's or the weather's name. `nil` uses the photo's name.
    public let title: String?

    public init(itemId: UUID, module: NetworkModules = .photo, mapId: UUID, anchor: CGPoint, title: String? = nil) {
        self.itemId = itemId
        self.module = module
        self.mapId = mapId
        self.anchor = anchor
        self.title = title
    }
}

public extension EnvironmentValues {
    /// Set on a display everyone at the table sees, such as an external screen. It leaves out
    /// anything only the game master's device opened.
    @Entry var isSharedDisplay = false
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
    /// Whether the photo in the popover is one only this device opened, such as the game
    /// master's hidden pin. A shared display (`\.isSharedDisplay`) does not draw it.
    public var isPrivate = false
    /// Installed by GameRPG for the length of a game. Holds no view.
    @ObservationIgnored public var actions: MapPhotoPopoverActions?
    /// Draws the picture of an item MapRPG cannot draw itself, such as a weather. Installed by
    /// GameRPG, which knows the module; type-erased because MapRPG does not depend on it.
    @ObservationIgnored public var itemPicture: (@MainActor (MapPhotoPopoverItem) -> AnyView)?

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
                itemId: photoId,
                module: .photo,
                mapId: mapId,
                anchor: pin.location,
                title: pin.name.isEmpty ? nil : pin.name
            ),
            isShared
        )
    }
}
