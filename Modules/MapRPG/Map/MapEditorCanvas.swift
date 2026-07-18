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

    var body: some View {
        ZStack(alignment: .topLeading) {
            MapViewportInteractionPlane(
                session: session,
                interactionTransform: $interactionTransform
            )

            MapLogicalCanvas(
                session: session,
                image: image,
                degrees: degrees,
                map: map,
                viewportScale: displayedTransform.scale,
                interactionTransform: $interactionTransform
            )
            .scaleEffect(displayedTransform.scale, anchor: .topLeading)
            .offset(
                x: displayedTransform.offset.x,
                y: displayedTransform.offset.y
            )

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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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

private struct MapViewportMetrics: Equatable {
    let size: CGSize
    let safeAreaInsets: EdgeInsets
}

private struct MapViewportInteractionPlane: View {
    let session: MapEditorSession
    let interactionTransform: GestureState<ViewportTransform?>

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        session: MapEditorSession,
        interactionTransform: GestureState<ViewportTransform?>
    ) {
        self.session = session
        self.interactionTransform = interactionTransform
    }

    private var isActive: Bool { session.mapMode != .viewer }

    var body: some View {
        Rectangle()
            .fill(.clear)
            .contentShape(.rect)
            .allowsHitTesting(isActive)
#if !os(tvOS)
            .gesture(tapGesture, including: isActive ? .all : .none)
            .modifier(
                MapViewportGestureModifier(
                    session: session,
                    interactionTransform: interactionTransform,
                    isEnabled: isActive
                )
            )
#endif
    }

#if !os(tvOS)
    private var tapGesture: some Gesture {
        SpatialTapGesture(count: 2)
            .exclusively(before: SpatialTapGesture(count: 1))
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

/// Installs the same combined viewport gesture on the background interaction
/// plane and on interactive room hit targets. This keeps panning available over
/// room interiors without allowing pin or needle drags to move the canvas.
struct MapViewportGestureModifier: ViewModifier {
    let session: MapEditorSession
    let interactionTransform: GestureState<ViewportTransform?>
    let isEnabled: Bool

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
        DragGesture(
            minimumDistance: 5,
            coordinateSpace: .named(MapViewportCoordinateSpace.name)
        )
        .simultaneously(with: MagnifyGesture())
        .updating(interactionTransform) { value, state, _ in
            state = transientTransform(for: value)
        }
        .onEnded { value in
            session.viewport.commit(transientTransform(for: value))
        }
    }

    private func transientTransform(
        for value: SimultaneousGesture<DragGesture, MagnifyGesture>.Value
    ) -> ViewportTransform {
        let translation = value.first?.translation ?? .zero
        let magnification = value.second?.magnification ?? 1
        let anchor = value.second.map { magnification in
            CGPoint(
                x: session.viewport.configuration.containerSize.width * magnification.startAnchor.x,
                y: session.viewport.configuration.containerSize.height * magnification.startAnchor.y
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

private struct MapLogicalCanvas: View {
    let session: MapEditorSession
    let image: AKImage
    let degrees: Double
    let map: MapModel
    let viewportScale: CGFloat
    let interactionTransform: GestureState<ViewportTransform?>

    private var canvasSize: CGSize { session.mapCanvasSize }
    private var activeEntryId: UUID? { session.editEntries.entries.first?.id }
    private var displayConfig: DisplayConfigModel {
        session.workingCopy?.displayConfig ?? map.displayConfig
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            MapOrientedImage(image: image, degrees: degrees, canvasSize: canvasSize)
                .allowsHitTesting(false)

            if !session.configuration.isTileEditor {
                MapPassiveRoomCanvas(
                    rooms: session.entries,
                    displayMode: session.displayMode,
                    displayConfig: displayConfig,
                    phase: .base,
                    mapImage: image,
                    degrees: degrees,
                    canvasSize: canvasSize,
                    excludingEntryId: activeEntryId
                )

                MapRoomHitLayer(
                    rooms: session.entries,
                    session: session,
                    isEnabled: roomHitTargetsAreEnabled,
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

                MapPassiveRoomCanvas(
                    rooms: session.entries,
                    displayMode: session.displayMode,
                    displayConfig: displayConfig,
                    phase: .fog,
                    mapImage: image,
                    degrees: degrees,
                    canvasSize: canvasSize,
                    excludingEntryId: activeEntryId
                )

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

            if session.mapMode == .edit {
                MapActiveRoomLayer(
                    rooms: session.editEntries,
                    displayMode: session.displayMode,
                    displayConfig: displayConfig,
                    mapImage: image,
                    degrees: degrees,
                    canvasSize: canvasSize
                )

                if session.displayMode == .master || session.displayMode == .reader,
                   let entryId = activeEntryId {
                    MapNeedleLayer(
                        entries: session.editEntries,
                        entryId: entryId,
                        session: session,
                        viewportScale: viewportScale
                    )
                }
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height, alignment: .topLeading)
    }

    private var roomHitTargetsAreEnabled: Bool {
        guard session.displayMode == .master else { return false }
        return switch session.mapMode {
        case .edit:
            session.editEntries.entries.isEmpty
        case .gameMaster:
            true
        case .player, .viewer:
            false
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
