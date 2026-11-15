// @copyright André Trettin

import CoreRPG
import SwiftUI

// Split out of this file — see CODE_AUDIT §9.13:
// - MapEditorCanvasGestures.swift: viewport interaction/gesture plumbing
// - MapEditorCanvasLayers.swift: the compositing layer views
// - MapEditorCanvasPins.swift: pin-layer views

enum MapViewportCoordinateSpace {
    static let name = "MapEditorViewport"
}

struct MapEditorCanvas: View {
    let session: MapEditorSession
    let image: AKImage
    let degrees: Double
    let map: MapModel

    @GestureState private var interactionTransform: ViewportTransform?
    @State private var safeAreaInsets = EdgeInsets()

    private var displayedTransform: ViewportTransform {
        interactionTransform ?? session.viewport.transform
    }

    /// The room/fog/active-room Canvas layers render into this — the visible
    /// viewport — rather than the (often huge) logical map size, applying
    /// pan/zoom inside their own `GraphicsContext` instead of inheriting it
    /// from an ancestor `.scaleEffect`. See `MapPassiveRoomCanvas`'s
    /// `viewportSize` doc comment for why.
    private var viewportSize: CGSize {
        session.viewport.configuration.containerSize
    }

    var body: some View {
        // Only this transparent window plane participates in layout. The
        // logical map has a fixed (often very large) size and must not be
        // allowed to become the canvas's ideal size: doing so makes the map
        // measure itself as the viewport, produces a false fit scale of 1,
        // and prevents the user from pinching back out to the real window fit.
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .topLeading) {
                MapViewportInteractionPlane(
                    session: session,
                    interactionTransform: $interactionTransform,
                    surface: .viewport
                )
            }
            .overlay(alignment: .topLeading) {
                MapLogicalCanvasBaseLayer(
                    session: session,
                    image: image,
                    degrees: degrees,
                    interactionTransform: $interactionTransform
                )
                .modifier(MapLogicalTransformModifier(transform: displayedTransform))
            }
            .overlay(alignment: .topLeading) {
                // The GM boundary/dim overlay (.master/.reader). Rendered in
                // viewport space, not inside the scaled layer above — see
                // MapPassiveRoomCanvas.
                MapRoomOverlayCanvas(
                    session: session,
                    map: map,
                    image: image,
                    degrees: degrees,
                    phase: .base,
                    transform: displayedTransform,
                    viewportSize: viewportSize
                )
            }
            .overlay(alignment: .topLeading) {
                MapLogicalCanvasHitAndOrdinaryPins(
                    session: session,
                    viewportScale: displayedTransform.scale,
                    roomHitCullingRect: MapRoomHitLayer.hitCullingRect(transform: displayedTransform, viewportSize: viewportSize),
                    interactionTransform: $interactionTransform
                )
                .modifier(MapLogicalTransformModifier(transform: displayedTransform))
            }
            .overlay(alignment: .topLeading) {
                // The player's fog-of-war. Sits above ordinary pins (hiding
                // them when their room is unrevealed) but below the pointer
                // and photo-shared pins layered in next, matching the original
                // single-ZStack ordering.
                MapRoomOverlayCanvas(
                    session: session,
                    map: map,
                    image: image,
                    degrees: degrees,
                    phase: .fog,
                    transform: displayedTransform,
                    viewportSize: viewportSize
                )
            }
            .overlay(alignment: .topLeading) {
                MapLogicalCanvasPointerAndPhotoSharedPins(
                    session: session,
                    viewportScale: displayedTransform.scale
                )
                .modifier(MapLogicalTransformModifier(transform: displayedTransform))
            }
            .overlay(alignment: .topLeading) {
                MapActiveRoomOverlayCanvas(
                    session: session,
                    map: map,
                    image: image,
                    degrees: degrees,
                    transform: displayedTransform,
                    viewportSize: viewportSize
                )
            }
            .overlay(alignment: .topLeading) {
                MapPencilStrokeOverlay(session: session, transform: displayedTransform)
            }
            .overlay(alignment: .topLeading) {
                MapLogicalCanvasNeedleLayer(
                    session: session,
                    viewportScale: displayedTransform.scale
                )
                .modifier(MapLogicalTransformModifier(transform: displayedTransform))
            }
            .overlay(alignment: .topLeading) {
                MapViewportOverlayLayer(
                    session: session,
                    image: image,
                    degrees: degrees,
                    transform: displayedTransform,
                    safeAreaInsets: safeAreaInsets
                )
                // Menus and the loupe live in viewport space and must remain above
                // every transformed map hit target, including selected needles.
                .zIndex(100)
            }
            .overlay {
                MapDisplayModeAnnouncementOverlay(session: session)
            }
            .coordinateSpace(name: MapViewportCoordinateSpace.name)
            .clipped()
            .onGeometryChange(for: MapViewportMetrics.self) { proxy in
                MapViewportMetrics(
                    size: proxy.size,
                    safeAreaInsets: proxy.safeAreaInsets
                )
            } action: { metrics in
                safeAreaInsets = metrics.safeAreaInsets
                session.updateContainerSize(metrics.size)
            }
    }
}

/// Applies the shared pan/zoom to the (non-Canvas) logical-canvas layers —
/// the same `.scaleEffect` + `.offset` pair, factored out since it now
/// applies separately to several sibling layers instead of one ZStack.
struct MapLogicalTransformModifier: ViewModifier {
    let transform: ViewportTransform

    func body(content: Content) -> some View {
        content
            .scaleEffect(transform.scale, anchor: .topLeading)
            .offset(x: transform.offset.x, y: transform.offset.y)
    }
}

private struct MapViewportMetrics: Equatable {
    let size: CGSize
    let safeAreaInsets: EdgeInsets
}

#Preview("Map editor canvas", traits: .mockData) {
    let image = AKImage()
    let session = MapEditorSession(
        map: .preview,
        image: image,
        photoDegrees: 0,
        containerSize: CGSize(width: 640, height: 480),
        mapMode: .gameMaster
    )

    MapEditorCanvas(
        session: session,
        image: image,
        degrees: 0,
        map: .preview
    )
    .frame(width: 640, height: 480)
}
