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
