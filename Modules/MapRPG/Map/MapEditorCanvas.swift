// @copyright André Trettin

import CoreRPG
import SwiftUI

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
                    interactionTransform: $interactionTransform
                )
                .modifier(MapLogicalTransformModifier(transform: displayedTransform))
            }
            .overlay(alignment: .topLeading) {
                // The player's fog-of-war. Sits above ordinary pins (hiding
                // them when their room is unrevealed) but below the pointer
                // and zoomed pins layered in next, matching the original
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
                MapLogicalCanvasPointerAndZoomedPins(
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
private struct MapLogicalTransformModifier: ViewModifier {
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

private struct MapViewportInteractionPlane: View {
    let session: MapEditorSession
    let interactionTransform: GestureState<ViewportTransform?>
    let surface: MapViewportGestureSurface

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        session: MapEditorSession,
        interactionTransform: GestureState<ViewportTransform?>,
        surface: MapViewportGestureSurface
    ) {
        self.session = session
        self.interactionTransform = interactionTransform
        self.surface = surface
    }

    private var isActive: Bool { session.mapMode != .viewer }

    var body: some View {
        Rectangle()
            .fill(.clear)
            .contentShape(.rect)
            .allowsHitTesting(isActive)
#if !os(tvOS)
            .gesture(
                tapGesture,
                including: isActive && !session.isPointerInteractionActive ? .all : .none
            )
            .modifier(
                MapPointerTapGestureModifier(
                    session: session,
                    isEnabled: session.isPointerInteractionActive
                )
            )
            .modifier(
                MapViewportGestureModifier(
                    session: session,
                    interactionTransform: interactionTransform,
                    isEnabled: isActive && !session.isPointerInteractionActive,
                    surface: surface
                )
            )
#endif
    }

#if !os(tvOS)
    private var tapGesture: some Gesture {
        SpatialTapGesture(
            count: 2,
            coordinateSpace: .named(MapViewportCoordinateSpace.name)
        )
            .exclusively(
                before: SpatialTapGesture(
                    count: 1,
                    coordinateSpace: .named(MapViewportCoordinateSpace.name)
                )
            )
            .onEnded { value in
                switch value {
                case .first(let doubleTap):
                    withAnimation(reduceMotion ? nil : .default) {
                        session.viewport.commit(
                            session.viewport.geometry.doubleTapped(
                                from: session.viewport.transform,
                                at: doubleTap.location
                            )
                        )
                    }
                case .second(let singleTap):
                    session.route(.canvasTap(singleTap.location))
                }
            }
    }

#endif
}

/// Pointer mode owns a direct single-tap recognizer. It deliberately bypasses
/// double-tap and long-press recognition so the pointer appears without their
/// failure delay, including when a room hit target covers the map surface.
struct MapPointerTapGestureModifier: ViewModifier {
    let session: MapEditorSession
    let isEnabled: Bool

    func body(content: Content) -> some View {
#if os(tvOS)
        content
#else
        content.highPriorityGesture(
            SpatialTapGesture(
                coordinateSpace: .named(MapViewportCoordinateSpace.name)
            )
                .onEnded { value in
                    session.route(.canvasTap(value.location))
                },
            including: isEnabled ? .all : .none
        )
#endif
    }
}

/// Installs the same combined viewport gesture on the background interaction
/// plane and on interactive room hit targets. This keeps panning available over
/// room interiors without allowing pin or needle drags to move the canvas.
struct MapViewportGestureModifier: ViewModifier {
    let session: MapEditorSession
    let interactionTransform: GestureState<ViewportTransform?>
    let isEnabled: Bool
    var surface: MapViewportGestureSurface = .viewport

    func body(content: Content) -> some View {
#if os(tvOS)
        content
#else
        content.simultaneousGesture(
            viewportGesture,
            including: isEnabled ? .all : .none
        )
#endif
    }

#if !os(tvOS)
    private var viewportGesture: some Gesture {
        MagnifyGesture(minimumScaleDelta: 0)
            .simultaneously(
                with: DragGesture(
                    minimumDistance: 3,
                    coordinateSpace: .named(MapViewportCoordinateSpace.name)
                )
            )
            .updating(interactionTransform) { value, state, _ in
                state = transientTransform(for: value)
            }
            .onEnded { value in
                session.viewport.commit(transientTransform(for: value))
            }
    }

    private func transientTransform(
        for value: SimultaneousGesture<MagnifyGesture, DragGesture>.Value
    ) -> ViewportTransform {
        let translation = value.second?.translation ?? .zero
        let magnification = value.first?.magnification ?? 1
        let anchor = value.first.map {
            surface.viewportAnchor(
                forStartLocation: $0.startLocation,
                session: session
            )
        } ?? session.viewport.geometry.containerCenter
        return session.viewport.geometry.interacting(
            from: session.viewport.transform,
            translation: translation,
            magnification: magnification,
            anchor: anchor
        )
    }
#endif
}

enum MapViewportGestureSurface {
    case viewport
    case content(CGSize)

    @MainActor
    func viewportAnchor(
        forStartLocation startLocation: CGPoint,
        session: MapEditorSession
    ) -> CGPoint {
        switch self {
        case .viewport:
            return startLocation
        case .content:
            return session.viewport.geometry.viewportPoint(
                fromContent: startLocation,
                transform: session.viewport.transform
            )
        }
    }
}

/// Image and the invisible interaction surface — vector/texture content that
/// scales cleanly through an ancestor `.scaleEffect`, unlike the room/fog
/// Canvas layers (see `MapRoomOverlayCanvas`).
private struct MapLogicalCanvasBaseLayer: View {
    let session: MapEditorSession
    let image: AKImage
    let degrees: Double
    let interactionTransform: GestureState<ViewportTransform?>

    private var canvasSize: CGSize { session.mapCanvasSize }

    var body: some View {
        ZStack(alignment: .topLeading) {
            MapOrientedImage(image: image, degrees: degrees, canvasSize: canvasSize)
                .allowsHitTesting(false)

            // Keep an interaction surface in the logical canvas as well as
            // behind it. Passive drawing layers deliberately do not receive
            // hits, but their full-size containers can otherwise prevent a
            // pinch from reaching the background plane on editor surfaces.
            // Pins, room hit targets, and needles are rendered above this
            // plane and retain their higher-priority gestures.
            MapViewportInteractionPlane(
                session: session,
                interactionTransform: interactionTransform,
                surface: .content(canvasSize)
            )
        }
        .frame(width: canvasSize.width, height: canvasSize.height, alignment: .topLeading)
    }
}

/// Room hit targets and ordinary pins — sits below the fog-of-war overlay so
/// fog can hide an ordinary pin whose room is unrevealed.
private struct MapLogicalCanvasHitAndOrdinaryPins: View {
    let session: MapEditorSession
    let viewportScale: CGFloat
    let interactionTransform: GestureState<ViewportTransform?>

    private var canvasSize: CGSize { session.mapCanvasSize }
    private var activeEntryId: UUID? { session.editEntries.entries.first?.id }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if !session.configuration.isTileEditor {
                MapRoomHitLayer(
                    rooms: session.entries,
                    session: session,
                    isEnabled: session.roomHitTargetsAreEnabled,
                    excludingEntryId: activeEntryId,
                    interactionTransform: interactionTransform
                )

                MapPinLayer(
                    pins: session.pins,
                    kind: .ordinary,
                    displayMode: session.displayMode,
                    mapMode: session.mapMode,
                    playerPinId: session.playerPinId,
                    pinScale: session.pinScale,
                    viewportScale: viewportScale
                )
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height, alignment: .topLeading)
    }
}

/// The pointer and zoomed pins — sit above the fog-of-war overlay so they
/// stay visible even in an unrevealed room.
private struct MapLogicalCanvasPointerAndZoomedPins: View {
    let session: MapEditorSession
    let viewportScale: CGFloat

    private var canvasSize: CGSize { session.mapCanvasSize }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if !session.configuration.isTileEditor {
                MapPinLayer(
                    pins: session.pins,
                    kind: .pointer,
                    displayMode: session.displayMode,
                    mapMode: session.mapMode,
                    playerPinId: session.playerPinId,
                    pinScale: session.pinScale,
                    viewportScale: viewportScale
                )

                MapPinLayer(
                    pins: session.pins,
                    kind: .zoomed,
                    displayMode: session.displayMode,
                    mapMode: session.mapMode,
                    playerPinId: session.playerPinId,
                    pinScale: session.pinScale,
                    viewportScale: viewportScale
                )
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height, alignment: .topLeading)
    }
}

/// The selected room's needle-editing handles (edit mode only).
private struct MapLogicalCanvasNeedleLayer: View {
    let session: MapEditorSession
    let viewportScale: CGFloat

    private var canvasSize: CGSize { session.mapCanvasSize }
    private var activeEntryId: UUID? { session.editEntries.entries.first?.id }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if session.mapMode == .edit,
               session.displayMode == .master || session.displayMode == .reader,
               let entryId = activeEntryId {
                MapNeedleLayer(
                    entries: session.editEntries,
                    entryId: entryId,
                    session: session,
                    viewportScale: viewportScale
                )
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height, alignment: .topLeading)
    }
}

/// The GM boundary/dim overlay (`.base`) or the player's fog-of-war
/// (`.fog`). Unlike the layers above, this renders in viewport space and
/// applies pan/zoom inside its own `GraphicsContext` — see
/// `MapPassiveRoomCanvas`'s `viewportSize` doc comment for why that matters
/// for a large map fitted far below its native scale.
private struct MapRoomOverlayCanvas: View {
    let session: MapEditorSession
    let map: MapModel
    let image: AKImage
    let degrees: Double
    let phase: MapRoomCanvasPhase
    let transform: ViewportTransform
    let viewportSize: CGSize

    private var canvasSize: CGSize { session.mapCanvasSize }
    private var activeEntryId: UUID? { session.editEntries.entries.first?.id }
    private var displayConfig: DisplayConfigModel {
        session.workingCopy?.displayConfig ?? map.displayConfig
    }

    var body: some View {
        if !session.configuration.isTileEditor {
            MapPassiveRoomCanvas(
                rooms: session.entries,
                displayMode: session.displayMode,
                displayConfig: displayConfig,
                phase: phase,
                mapImage: image,
                degrees: degrees,
                canvasSize: canvasSize,
                transform: transform,
                viewportSize: viewportSize,
                excludingEntryId: activeEntryId
            )
        }
    }
}

/// The currently-edited room's own boundary/fog preview (edit mode only),
/// in the same viewport-space style as `MapRoomOverlayCanvas`.
private struct MapActiveRoomOverlayCanvas: View {
    let session: MapEditorSession
    let map: MapModel
    let image: AKImage
    let degrees: Double
    let transform: ViewportTransform
    let viewportSize: CGSize

    private var canvasSize: CGSize { session.mapCanvasSize }
    private var displayConfig: DisplayConfigModel {
        session.workingCopy?.displayConfig ?? map.displayConfig
    }

    var body: some View {
        if session.mapMode == .edit {
            MapActiveRoomLayer(
                rooms: session.editEntries,
                displayMode: session.displayMode,
                displayConfig: displayConfig,
                mapImage: image,
                degrees: degrees,
                canvasSize: canvasSize,
                transform: transform,
                viewportSize: viewportSize
            )
        }
    }
}

private enum MapPinLayerKind {
    case ordinary
    case pointer
    case zoomed
}

private struct MapPinLayer: View {
    let pins: MapPinViewModel
    let kind: MapPinLayerKind
    let displayMode: MapDisplayMode
    let mapMode: MapMode
    let playerPinId: UUID?
    let pinScale: CGFloat
    let viewportScale: CGFloat

    var body: some View {
        switch kind {
        case .ordinary:
            ForEach(pins.ordinaryPinNodes) { node in
                MapPinLayerItem(
                    node: node,
                    displayMode: displayMode,
                    mapMode: mapMode,
                    playerPinId: playerPinId,
                    pinScale: pinScale,
                    viewportScale: viewportScale
                )
            }
        case .pointer:
            MapPinLayerItem(
                node: pins.pointerNode,
                displayMode: displayMode,
                mapMode: mapMode,
                playerPinId: playerPinId,
                pinScale: pinScale,
                viewportScale: viewportScale
            )
        case .zoomed:
            ForEach(pins.zoomedPinNodes) { node in
                MapPinLayerItem(
                    node: node,
                    displayMode: displayMode,
                    mapMode: mapMode,
                    playerPinId: playerPinId,
                    pinScale: pinScale,
                    viewportScale: viewportScale
                )
            }
        }
    }
}

private struct MapPinLayerItem: View {
    let node: MapPinNode
    let displayMode: MapDisplayMode
    let mapMode: MapMode
    let playerPinId: UUID?
    let pinScale: CGFloat
    let viewportScale: CGFloat

    private var isVisible: Bool {
        if node.isPointer, !node.pin.isShown { return false }
        return displayMode != .player || node.pin.isShown
    }

    private var canDrag: Bool {
        mapMode == .edit
            || mapMode == .gameMaster
            || (mapMode == .player && (node.id == playerPinId || node.isPointer))
    }

    private var actionContext: MapPinActionContext {
        guard !node.isPointer else { return .none }
        return switch mapMode {
        case .edit: .editor
        case .gameMaster: .gameMaster
        case .player, .viewer: .none
        }
    }

    private var doubleTapAccessibilityLabel: LocalizedStringResource {
        if node.isPointer || mapMode == .edit {
            LocalizedStringResource("Toggle Player Visibility", bundle: .module)
        } else {
            LocalizedStringResource("Toggle Pin Zoom", bundle: .module)
        }
    }

    var body: some View {
        if isVisible {
            MapPinActionView(
                model: node,
                pinScale: pinScale,
                canDrag: canDrag,
                actionContext: actionContext,
                doubleTapAccessibilityLabel: doubleTapAccessibilityLabel,
                viewportScale: viewportScale
            )
            .allowsHitTesting(mapMode != .viewer)
        }
    }
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
