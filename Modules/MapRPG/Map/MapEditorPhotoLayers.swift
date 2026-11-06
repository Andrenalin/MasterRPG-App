// @copyright André Trettin

import CoreRPG
import SwiftUI

/// The photo popover of one pin. Like the action menu it stays open while the map pans or
/// zooms and follows the pin; the same dismissals close it.
struct MapPinPhotoViewportLayer: View {
    let pins: MapPinViewModel
    let displayMode: MapDisplayMode
    let pinScale: CGFloat
    let transform: ViewportTransform
    let geometry: ViewportGeometry
    let viewportRectangle: CGRect
    let containerSize: CGSize
    let onShowFullScreen: ((MapPinModel) -> Void)?
    let onDismiss: () -> Void

    var body: some View {
        if let node = photoNode,
           displayMode != .player || node.pin.isShown,
           let source = MapPinPopoverSource.rectangle(
               for: node.pin,
               pinScale: pinScale,
               transform: transform,
               geometry: geometry
           ) {
            MapPopover(
                source: source,
                viewportRectangle: viewportRectangle,
                onDismiss: onDismiss
            ) {
                MapPinPhotoPopoverContent(
                    pin: node.pin,
                    onShowFullScreen: onShowFullScreen.map { action in { action(node.pin) } },
                    onClose: onDismiss
                )
            }
            .frame(
                width: containerSize.width,
                height: containerSize.height,
                alignment: .topLeading
            )
            .transition(.opacity)
            .zIndex(10)
        }
    }

    private var photoNode: MapPinNode? {
        pins.photoPinId.flatMap(pins.pinNode(for:))
    }
}

/// A photo the game master shows on the game map, in the pin photo popover pointing at the room
/// it belongs to. It follows the map while it pans or zooms. A tap on the map does not close it:
/// on the game master's device that would close it for every player. Its own Close button and
/// Escape do.
struct MapPhotoViewportLayer: View {
    let mapId: UUID
    let mode: MapMode
    let transform: ViewportTransform
    let geometry: ViewportGeometry
    let viewportRectangle: CGRect
    let containerSize: CGSize

    @Environment(MapRootModel.self) private var root
    @Environment(\.isSharedDisplay) private var isSharedDisplay

    var body: some View {
        let popover = root.photoPopover
        if mode == .gameMaster || mode == .player,
           !(isSharedDisplay && popover.isPrivate),
           let photo = popover.photo(on: mapId),
           let source = MapPhotoPopoverSource.rectangle(
               for: photo.anchor,
               transform: transform,
               geometry: geometry
           ) {
            MapPopover(
                source: source,
                viewportRectangle: viewportRectangle,
                onDismiss: { popover.close() }
            ) {
                MapPhotoPopoverContent(
                    item: photo,
                    onShowFullScreen: { popover.showFullScreen() },
                    onClose: { popover.close() }
                )
            }
            .frame(
                width: containerSize.width,
                height: containerSize.height,
                alignment: .topLeading
            )
            .id(photo.itemId)
            .transition(.opacity)
            .zIndex(11)
        }
    }
}

/// A point as a popover source: a one-point rectangle in viewport coordinates.
public enum MapPhotoPopoverSource {
    /// The one-point rectangle around a point already in viewport coordinates; `nil` when the
    /// point is not finite. Used by the camera-based 3D table, which projects its own points.
    public static func rectangle(atViewportPoint point: CGPoint) -> CGRect? {
        guard point.x.isFinite, point.y.isFinite else { return nil }
        return CGRect(x: point.x - 0.5, y: point.y - 0.5, width: 1, height: 1)
    }

    /// The same for a point of the map's content.
    static func rectangle(
        for anchor: CGPoint,
        transform: ViewportTransform,
        geometry: ViewportGeometry
    ) -> CGRect? {
        rectangle(atViewportPoint: geometry.viewportPoint(fromContent: anchor, transform: transform))
    }
}
