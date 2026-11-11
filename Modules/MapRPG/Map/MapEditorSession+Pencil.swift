// @copyright André Trettin

import CoreGraphics
import CoreRPG
import SwiftUI

// Apple Pencil room drawing — see `MapPencilStroke` for the geometry.

extension MapEditorSession {
    /// Pencil drawing edits room outlines, so it exists in the room editor only. It needs the
    /// SwiftUI input kinds of iOS 27 to tell the pencil from fingers.
    var canDrawWithPencil: Bool {
#if os(iOS)
        if #available(iOS 27.0, *) {
            return mapMode == .edit && !configuration.isTileEditor
        }
#endif
        return false
    }

    func setPencilDrawing(_ isOn: Bool) {
        let isOn = isOn && canDrawWithPencil
        guard isPencilDrawing != isOn else { return }
        isPencilDrawing = isOn
        pencilStroke.removeAll()
        pencilStrokeOrigin = nil
        if isOn {
            clearSelections()
        }
    }

    /// Starts a new outline where the pencil landed, discarding any unfinished one.
    func beginPencilStroke(atViewport location: CGPoint) {
        pencilStroke.removeAll()
        pencilStrokeOrigin = location
        extendPencilStroke(toViewport: location)
    }

    /// Adds the pencil's current position (viewport coordinates) to the outline being drawn.
    func extendPencilStroke(toViewport location: CGPoint) {
        guard isPencilDrawing else { return }
        let scale = max(viewport.transform.scale, .leastNonzeroMagnitude)
        pencilStroke.append(
            contentPoint(fromViewport: location),
            minimumDistance: MapPencilStroke.sampleScreenDistance / scale
        )
    }

    /// Lifts the pencil: the outline becomes the room's shape, unless it is too small for a room.
    func finishPencilStroke() {
        defer {
            pencilStroke.removeAll()
            pencilStrokeOrigin = nil
        }
        guard isPencilDrawing,
              let polygon = pencilStroke.polygon(scale: viewport.transform.scale) else { return }
        route(.pencilRoom(polygon))
    }

}
