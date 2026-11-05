// @copyright André Trettin

#if os(iOS) || os(macOS) || os(visionOS)
import CoreGraphics
import CoreRPG
import Foundation
import MapRPG
import RealityKit
import SwiftUI

extension GameTableModel {
    // MARK: - Map Photo Popover

    /// The photo the game master shows on the current map (see `MapPhotoPopoverModel`), `nil`
    /// when none is shown or it belongs to another map.
    var mapPhoto: MapPhotoPopoverItem? {
        mapRoot.photoPopover.photo(on: currentMapId)
    }

    /// Places the photo's anchor on the table: after a map sync and when the photo changes.
    /// Skips an unchanged position, because it runs on every map sync.
    func updateMapPhotoAnchor() {
        let position = mapPhotoTablePosition()
        if mapPhotoPosition != position {
            mapPhotoPosition = position
        }
        updateMapPhotoAttachmentPosition()
#if !os(visionOS)
        if position == nil, mapPhotoSource != nil {
            mapPhotoSource = nil
        }
#endif
    }

    /// The anchor in the pin container's space, raised like a pin token.
    private func mapPhotoTablePosition() -> SIMD3<Float>? {
        guard let photo = mapPhoto,
              let mapImage = currentMapImage,
              let canvasSize = MapTableProjection.canvasSize(
                  map: currentMapModel(),
                  image: mapImage,
                  degrees: currentMapDegrees
              )
        else { return nil }
        let projection = MapTableProjection(
            imageSize: canvasSize,
            planeAspectRatio: MapTableProjection.planeAspectRatio(
                photoSize: mapImage.size,
                degrees: currentMapDegrees,
                canvasSize: canvasSize
            )
        )
        return projection.tablePosition(for: photo.anchor)
    }

    func updateMapPhotoAttachmentPosition() {
        guard let position = mapPhotoPosition else {
            mapPhotoPopover.hide()
            return
        }
        mapPhotoPopover.show(at: SIMD3<Float>(
            position.x,
            position.y + Self.pinMenuArrowTipHeight,
            position.z
        ))
    }

    /// Registers the SwiftUI attachment used for the map photo popover.
    func registerMapPhotoAttachment(_ attachment: Entity) {
        mapPhotoPopover.register(attachment, in: renderer.root)
        updateMapPhotoAttachmentPosition()
    }

    func mapPhotoAttachmentHeightChanged(_ height: Float) {
        mapPhotoPopover.attachmentHeightChanged(height)
    }

    func detachMapPhotoAttachment() {
        mapPhotoPopover.detach()
    }

#if !os(visionOS)
    /// Projects the photo's anchor into the table view for the popover. Runs every rendered
    /// frame next to `updatePinPhotoSource(project:)`.
    func updateMapPhotoSource(project: (SIMD3<Float>) -> CGPoint?) {
        guard let photo = mapPhoto,
              let position = mapPhotoPosition,
              let point = project(setup.pinContainer.convert(position: position, to: nil)),
              point.x.isFinite, point.y.isFinite
        else {
            if mapPhotoSource != nil {
                mapPhotoSource = nil
            }
            return
        }
        let source = TablePinMenuSource(
            pinId: photo.photoId,
            frame: CGRect(x: point.x - 0.5, y: point.y - 0.5, width: 1, height: 1)
        )
        if source.differsVisibly(from: mapPhotoSource) {
            mapPhotoSource = source
        }
    }
#endif
}

#endif
