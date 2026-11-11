// @copyright André Trettin

import CoreRPG
import SwiftUI

// Split out of MapEditorCanvas.swift — see CODE_AUDIT §9.13.

struct MapViewportInteractionPlane: View {
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
            .modifier(MapPencilDrawGestureModifier(session: session))
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
    /// A tap that, while the pencil draws, ignores the pencil.
    private func viewportTap(count: Int) -> SpatialTapGesture {
#if os(iOS)
        if #available(iOS 27.0, *), session.isPencilDrawing {
            return SpatialTapGesture(
                count: count,
                coordinateSpace: .named(MapViewportCoordinateSpace.name),
                inputKinds: session.viewportInputKinds
            )
        }
#endif
        return SpatialTapGesture(
            count: count,
            coordinateSpace: .named(MapViewportCoordinateSpace.name)
        )
    }

    private var tapGesture: some Gesture {
        viewportTap(count: 2)
            .exclusively(before: viewportTap(count: 1))
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
        viewportMagnify
            .simultaneously(with: viewportDrag)
            .updating(interactionTransform) { value, state, _ in
                state = transientTransform(for: value)
            }
            .onEnded { value in
                session.viewport.commit(transientTransform(for: value))
            }
    }

    /// The viewport gestures ignore the pencil while it draws, so it never pans the map.
    private var viewportMagnify: MagnifyGesture {
#if os(iOS)
        if #available(iOS 27.0, *), session.isPencilDrawing {
            return MagnifyGesture(minimumScaleDelta: 0, inputKinds: session.viewportInputKinds)
        }
#endif
        return MagnifyGesture(minimumScaleDelta: 0)
    }

    private var viewportDrag: DragGesture {
#if os(iOS)
        if #available(iOS 27.0, *), session.isPencilDrawing {
            return DragGesture(
                minimumDistance: 3,
                coordinateSpace: .named(MapViewportCoordinateSpace.name),
                inputKinds: session.viewportInputKinds
            )
        }
#endif
        return DragGesture(
            minimumDistance: 3,
            coordinateSpace: .named(MapViewportCoordinateSpace.name)
        )
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

/// Apple Pencil room drawing. While the toolbar's draw mode is on, the pencil draws an outline
/// (live preview in `MapPencilStrokeOverlay`) and a pencil tap adds a single point, while the
/// viewport gestures ignore the pencil, so fingers keep panning and zooming. Needles and pins
/// keep their own, closer gestures, so the pencil can still move them.
struct MapPencilDrawGestureModifier: ViewModifier {
    let session: MapEditorSession

    func body(content: Content) -> some View {
#if os(iOS)
        if #available(iOS 27.0, *) {
            content
                .simultaneousGesture(drawGesture, isEnabled: session.isPencilDrawing)
                .simultaneousGesture(tapGesture, isEnabled: session.isPencilDrawing)
        } else {
            content
        }
#else
        content
#endif
    }

#if os(iOS)
    @available(iOS 27.0, *)
    private var drawGesture: some Gesture {
        DragGesture(
            minimumDistance: 3,
            coordinateSpace: .named(MapViewportCoordinateSpace.name),
            inputKinds: .pencil
        )
            .onChanged { value in
                if session.pencilStrokeOrigin != value.startLocation {
                    // The drag only starts after `minimumDistance`; keep where the pencil landed.
                    session.beginPencilStroke(atViewport: value.startLocation)
                }
                session.extendPencilStroke(toViewport: value.location)
            }
            .onEnded { value in
                session.extendPencilStroke(toViewport: value.location)
                session.finishPencilStroke()
            }
    }

    @available(iOS 27.0, *)
    private var tapGesture: some Gesture {
        SpatialTapGesture(
            coordinateSpace: .named(MapViewportCoordinateSpace.name),
            inputKinds: .pencil
        )
            .onEnded { value in
                session.route(.canvasTap(value.location))
            }
    }
#endif
}

#if os(iOS)
extension MapEditorSession {
    /// The inputs that pan, zoom and double-tap the map while the pencil draws: everything but
    /// the pencil.
    @available(iOS 27.0, *)
    var viewportInputKinds: GestureInputKinds {
        [.directTouch, .indirectTouch, .pointer]
    }
}
#endif

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
