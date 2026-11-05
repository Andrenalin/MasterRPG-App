// @copyright André Trettin

import CoreRPG
import SwiftUI

struct MapViewportOverlayLayer: View {
    let session: MapEditorSession
    let image: AKImage
    let degrees: Double
    let transform: ViewportTransform
    let safeAreaInsets: EdgeInsets

    @Environment(MapRootModel.self) private var root

    private var viewportRectangle: CGRect {
        CGRect(origin: .zero, size: session.viewport.configuration.containerSize)
    }

    /// The map stays full-screen; viewport controls go only in the unobscured rectangle.
    private var actionViewportRectangle: CGRect {
        .unobscuredViewport(
            size: session.viewport.configuration.containerSize,
            safeAreaInsets: safeAreaInsets
        )
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            MapPinViewportMenuLayer(
                pins: session.pins,
                mode: session.mapMode,
                pinScale: session.pinScale,
                transform: transform,
                geometry: session.viewport.geometry,
                viewportRectangle: actionViewportRectangle,
                containerSize: viewportRectangle.size,
                onDismiss: { session.clearSelections() }
            )

            MapPinPhotoViewportLayer(
                pins: session.pins,
                displayMode: session.displayMode,
                pinScale: session.pinScale,
                transform: transform,
                geometry: session.viewport.geometry,
                viewportRectangle: actionViewportRectangle,
                containerSize: viewportRectangle.size,
                onShowFullScreen: pinPhotoFullScreenAction,
                onDismiss: { session.route(.dismissPinPhoto) }
            )

            MapPhotoViewportLayer(
                mapId: session.mapId,
                mode: session.mapMode,
                transform: transform,
                geometry: session.viewport.geometry,
                viewportRectangle: actionViewportRectangle,
                containerSize: viewportRectangle.size
            )

            MapNeedleViewportMenuLayer(
                session: session,
                transform: transform,
                viewportRectangle: actionViewportRectangle,
                containerSize: viewportRectangle.size
            )

            MapNeedleLoupeLayer(
                interaction: session.rooms.needleDrag,
                image: image,
                degrees: degrees,
                canvasSize: session.mapCanvasSize,
                transform: transform,
                geometry: session.viewport.geometry,
                viewportRectangle: actionViewportRectangle
            )
        }
        .frame(
            width: viewportRectangle.width,
            height: viewportRectangle.height,
            alignment: .topLeading
        )
    }

    /// A pin photo goes full screen during a game: its popover closes (for every player when
    /// the game master shows it) and the photo opens full screen, for every player when the game
    /// master shows a pin they see.
    private var pinPhotoFullScreenAction: ((MapPinModel) -> Void)? {
        guard session.mapMode == .gameMaster || session.mapMode == .player,
              root.photoPopover.canShowFullScreen else { return nil }
        let popover = root.photoPopover
        let mapId = session.mapId
        let isGameMaster = session.mapMode == .gameMaster
        return { [session] pin in
            let isShared = isGameMaster && pin.isShown
            session.route(.dismissPinPhoto)
            popover.showFullScreen(pin: pin, mapId: mapId, isShared: isShared)
        }
    }
}

private struct MapPinViewportMenuLayer: View {
    let pins: MapPinViewModel
    let mode: MapMode
    let pinScale: CGFloat
    let transform: ViewportTransform
    let geometry: ViewportGeometry
    let viewportRectangle: CGRect
    let containerSize: CGSize
    let onDismiss: () -> Void

    var body: some View {
        if let node = expandedNode, context != .none, let source = pinRectangle(for: node) {
            MapPopover(
                source: source,
                viewportRectangle: viewportRectangle,
                onDismiss: onDismiss
            ) {
                MapPinActionMenuStack(model: node, context: context)
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

    private func pinRectangle(for node: MapPinNode) -> CGRect? {
        MapPinPopoverSource.rectangle(
            for: node.pin,
            pinScale: pinScale,
            transform: transform,
            geometry: geometry
        )
    }

    private var expandedNode: MapPinNode? {
        pins.isExpandedId.flatMap(pins.pinNode(for:))
    }

    private var context: MapPinActionContext {
        switch mode {
        case .edit: .editor
        case .gameMaster: .gameMaster
        case .player, .viewer: .none
        }
    }
}

/// The pin's on-screen frame, used as the source of its popovers. Derived from the displayed
/// transform, so a popover follows the pin while the map pans or zooms.
private enum MapPinPopoverSource {
    static func rectangle(
        for pin: MapPinModel,
        pinScale: CGFloat,
        transform: ViewportTransform,
        geometry: ViewportGeometry
    ) -> CGRect? {
        let center = geometry.viewportPoint(fromContent: pin.location, transform: transform)
        let size = pin.size.size * (pinScale * transform.scale)
        guard center.x.isFinite, center.y.isFinite,
              size.width.isFinite, size.height.isFinite else { return nil }
        let width = max(1, size.width)
        let height = max(1, size.height)
        return CGRect(
            x: center.x - width / 2,
            y: center.y - height / 2,
            width: width,
            height: height
        )
    }
}

/// The photo popover of one pin. Like the action menu it stays open while the map pans or
/// zooms and follows the pin; the same dismissals close it.
private struct MapPinPhotoViewportLayer: View {
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
private struct MapPhotoViewportLayer: View {
    let mapId: UUID
    let mode: MapMode
    let transform: ViewportTransform
    let geometry: ViewportGeometry
    let viewportRectangle: CGRect
    let containerSize: CGSize

    @Environment(MapRootModel.self) private var root

    var body: some View {
        let popover = root.photoPopover
        if mode == .gameMaster || mode == .player,
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
                    photoId: photo.photoId,
                    title: photo.title,
                    onShowFullScreen: { popover.showFullScreen() },
                    onClose: { popover.close() }
                )
            }
            .frame(
                width: containerSize.width,
                height: containerSize.height,
                alignment: .topLeading
            )
            .id(photo.photoId)
            .transition(.opacity)
            .zIndex(11)
        }
    }
}

/// A point on the map as a popover source: a one-point rectangle in viewport coordinates.
enum MapPhotoPopoverSource {
    static func rectangle(
        for anchor: CGPoint,
        transform: ViewportTransform,
        geometry: ViewportGeometry
    ) -> CGRect? {
        let center = geometry.viewportPoint(fromContent: anchor, transform: transform)
        guard center.x.isFinite, center.y.isFinite else { return nil }
        return CGRect(x: center.x - 0.5, y: center.y - 0.5, width: 1, height: 1)
    }
}

private struct MapNeedleViewportMenuLayer: View {
    let session: MapEditorSession
    let transform: ViewportTransform
    let viewportRectangle: CGRect
    let containerSize: CGSize

    var body: some View {
        if shouldShow,
           let entryId = session.editEntries.entries.first?.id,
           let point = session.editEntries.selectedNeedlePoint(for: entryId),
           let source = needleRectangle(for: point) {
            MapPopover(
                source: source,
                viewportRectangle: viewportRectangle,
                // A row above the needle head; below the needle when there is no room above.
                preferredSides: [.top, .bottom],
                onDismiss: { session.clearSelections() }
            ) {
                MapNeedleActionMenuRow(session: session, entryId: entryId, point: point)
            }
            .frame(
                width: containerSize.width,
                height: containerSize.height,
                alignment: .topLeading
            )
            // Keep the visual and hit-test frames colocated from the first
            // rendered frame. A scale transition leaves Button hit regions
            // at their destination while the glass is visibly elsewhere.
            .transition(.opacity)
            .zIndex(10)
        }
    }

    private var shouldShow: Bool {
        session.mapMode == .edit
            && (session.displayMode == .master || session.displayMode == .reader)
            && session.pins.isExpandedId == nil
            && session.rooms.needleDrag.dragCoordinate == nil
    }

    /// The needle's on-screen frame, from the top of its head down to its tip, used as the
    /// popover source: a panel below it never covers the point being edited.
    private func needleRectangle(for point: MapNeedlePointModel) -> CGRect? {
        let geometry = session.viewport.geometry
        // `NeedleMapPin` draws a 44-point head centered 88 points above its tip.
        let head = geometry.viewportPoint(
            fromContent: CGPoint(x: point.coordinate.x, y: point.coordinate.y - 88),
            transform: transform
        )
        let tip = geometry.viewportPoint(fromContent: point.coordinate, transform: transform)
        let headRadius = 22 * transform.scale
        guard head.x.isFinite, head.y.isFinite, tip.y.isFinite, headRadius.isFinite else { return nil }
        let top = head.y - headRadius
        return CGRect(
            x: head.x - headRadius,
            y: top,
            width: max(1, headRadius * 2),
            height: max(1, tip.y - top)
        )
    }
}

/// The selected needle's actions (remove the point, add one after it), laid out in a row.
private struct MapNeedleActionMenuRow: View {
    let session: MapEditorSession
    let entryId: UUID
    let point: MapNeedlePointModel

    var body: some View {
        HStack(spacing: MapPopoverLayout.contentInset) {
            ForEach(NeedleMapPinButtonType.allCases, id: \.self) { type in
                MapPopoverButton(
                    title: Text(type == .remove ? "Remove Point" : "Add Point", bundle: .module),
                    systemImage: type.systemImage,
                    tint: type == .remove ? .red : .teal
                ) {
                    perform(type)
                }
            }
        }
        .padding(MapPopoverLayout.contentInset)
    }

    private func perform(_ type: NeedleMapPinButtonType) {
        switch type {
        case .remove:
            session.editEntries.removeNeedle(point, entryId: entryId)
        case .add:
            session.editEntries.insertNeedle(after: point, entryId: entryId)
        }
        session.route(.needleCoordinatesChanged(entryId))
    }
}

private struct MapNeedleLoupeLayer: View {
    let interaction: MapNeedleInteractionModel
    let image: AKImage
    let degrees: Double
    let canvasSize: CGSize
    let transform: ViewportTransform
    let geometry: ViewportGeometry
    let viewportRectangle: CGRect

    var body: some View {
        if let sampleCoordinate = interaction.dragCoordinate {
            let logicalHead = CGPoint(x: sampleCoordinate.x, y: sampleCoordinate.y - 88)
            let viewportHead = geometry.viewportPoint(
                fromContent: logicalHead,
                transform: transform
            )
            let placement = MapLoupeGeometry.placement(
                needleHead: viewportHead,
                viewport: viewportRectangle,
                interaction: interactionKind
            )
            if placement.isValid {
                MapNeedleLoupe(
                    image: image,
                    degrees: degrees,
                    canvasSize: canvasSize,
                    sampleCoordinate: sampleCoordinate,
                    viewportScale: transform.scale
                )
                .position(placement.center)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
    }

    private var interactionKind: MapLoupeInteractionKind {
#if os(iOS)
        .touch
#else
        .pointerOrSpatial
#endif
    }
}

private struct MapNeedleLoupe: View {
    let image: AKImage
    let degrees: Double
    let canvasSize: CGSize
    let sampleCoordinate: CGPoint
    let viewportScale: CGFloat

    private var sampling: MapLoupeSampling {
        MapLoupeGeometry.sampling(
            sampleCoordinate: sampleCoordinate,
            viewportScale: viewportScale
        )
    }

    var body: some View {
        Canvas(opaque: false, colorMode: .nonLinear, rendersAsynchronously: false) { context, _ in
            guard let map = context.resolveSymbol(id: MapLoupeCanvasSymbol.map) else { return }
            context.draw(map, in: sampling.destinationRectangle(canvasSize: canvasSize))
        } symbols: {
            MapOrientedImage(image: image, degrees: degrees, canvasSize: canvasSize)
                .tag(MapLoupeCanvasSymbol.map)
        }
        .frame(width: MapLoupeGeometry.size.width, height: MapLoupeGeometry.size.height)
        .clipShape(.circle)
        .overlay {
            MapLoupeCrosshair()
                .stroke(
                    .green.opacity(0.8),
                    style: StrokeStyle(lineWidth: 5, lineCap: .round)
                )
        }
        .overlay {
            Circle().stroke(.black.opacity(0.8), lineWidth: 6)
        }
        .shadow(radius: 4)
    }
}

private enum MapLoupeCanvasSymbol: Hashable {
    case map
}

private struct MapLoupeCrosshair: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let horizontalGap = rect.width / 6
        let verticalGap = rect.height / 6
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX - horizontalGap, y: rect.midY))
        path.move(to: CGPoint(x: rect.midX + horizontalGap, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.midY - verticalGap))
        path.move(to: CGPoint(x: rect.midX, y: rect.midY + verticalGap))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        return path
    }
}

private struct MapViewportOverlayPreview: View {
    @State private var session: MapEditorSession
    private let image: AKImage

    init() {
        let image = AKImage()
        let session = MapEditorSession(
            map: .preview,
            image: image,
            photoDegrees: 0,
            containerSize: CGSize(width: 640, height: 480),
            mapMode: .gameMaster
        )
        session.pins.isExpandedId = session.pins.mapPinNodes.first?.id
        self.image = image
        _session = State(initialValue: session)
    }

    var body: some View {
        MapViewportOverlayLayer(
            session: session,
            image: image,
            degrees: 0,
            transform: session.viewport.transform,
            safeAreaInsets: EdgeInsets()
        )
        .frame(width: 640, height: 480)
    }
}

#Preview("Map viewport controls") {
    MapViewportOverlayPreview()
        .environment(MapRootModel.preview)
}
