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
        updateAttachmentPosition(for: .mapPhoto)
#if !os(visionOS)
        if position == nil {
            clearPopoverSource(for: .mapPhoto)
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
}

#endif
