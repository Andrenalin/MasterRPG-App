// @copyright André Trettin

import CoreRPG
import SwiftUI

/// The outline the Apple Pencil is drawing, with a dashed closing segment back to its start,
/// rendered in viewport space so the line keeps its width at every zoom level.
struct MapPencilStrokeOverlay: View {
    let session: MapEditorSession
    let transform: ViewportTransform

    var body: some View {
        let points = session.pencilStroke.points
        if session.isPencilDrawing, points.count > 1 {
            Canvas { context, _ in
                let viewportPoints = points.map { point in
                    session.viewport.geometry.viewportPoint(fromContent: point, transform: transform)
                }
                var outline = Path()
                outline.addLines(viewportPoints)
                var closing = Path()
                if let first = viewportPoints.first, let last = viewportPoints.last {
                    closing.move(to: last)
                    closing.addLine(to: first)
                }
                context.stroke(
                    closing,
                    with: .color(.accentColor.opacity(0.7)),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [6, 6])
                )
                context.stroke(
                    outline,
                    with: .color(.accentColor),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                )
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}
