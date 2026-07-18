// @copyright André Trettin

import CoreRPG
import SwiftUI

struct MapViewportOverlayLayer: View {
    let session: MapEditorSession
    let image: AKImage
    let degrees: Double
    let transform: ViewportTransform
    let safeAreaInsets: EdgeInsets

    private var viewportRectangle: CGRect {
        CGRect(origin: .zero, size: session.viewport.configuration.containerSize)
    }

    /// System bars and visionOS ornaments can visually cover the map without
    /// belonging to its hit-test tree. Keep the map full-screen, but place
    /// viewport controls only in the unobscured rectangle.
    private var actionViewportRectangle: CGRect {
        let top = safeInset(safeAreaInsets.top)
        let leading = safeInset(safeAreaInsets.leading)
        let bottom = safeInset(safeAreaInsets.bottom)
        let trailing = safeInset(safeAreaInsets.trailing)
        let rectangle = CGRect(
            x: viewportRectangle.minX + leading,
            y: viewportRectangle.minY + top,
            width: viewportRectangle.width - leading - trailing,
            height: viewportRectangle.height - top - bottom
        )
        guard rectangle.width > 0, rectangle.height > 0 else {
            return viewportRectangle
        }
        return rectangle
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            MapPinViewportMenuLayer(
                pins: session.pins,
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

    private func safeInset(_ value: CGFloat) -> CGFloat {
        value.isFinite ? max(0, value) : 0
    }
}

private struct MapPinViewportMenuLayer: View {
    let pins: MapPinViewModel
    let mode: MapMode
    let transform: ViewportTransform
    let geometry: ViewportGeometry
    let viewportRectangle: CGRect
    let containerSize: CGSize

    var body: some View {
        if let node = expandedNode, context != .none {
            let anchor = geometry.viewportPoint(fromContent: node.pin.location, transform: transform)
            let placement = MapAdaptiveFanGeometry.verticalPlacement(
                anchor: anchor,
                itemCount: context.actions.count,
                viewport: viewportRectangle,
                preferredDirection: .bottom
            )
            if placement.isValid {
                MapPinExpandedMenu(
                    model: node,
                    context: context,
                    placement: placement,
                    usesGlassEffects: true
                )
                .frame(
                    width: containerSize.width,
                    height: containerSize.height,
                    alignment: .topLeading
                )
                // Scale transitions can temporarily separate Liquid Glass
                // rendering from Button hit regions on touch/spatial input.
                .transition(.opacity)
                .zIndex(10)
            }
        }
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

private struct MapNeedleViewportMenuLayer: View {
    let session: MapEditorSession
    let transform: ViewportTransform
    let viewportRectangle: CGRect
    let containerSize: CGSize

    var body: some View {
        if shouldShow,
           let entryId = session.editEntries.entries.first?.id,
           let point = session.editEntries.selectedNeedlePoint(for: entryId) {
            let head = CGPoint(x: point.coordinate.x, y: point.coordinate.y - 88)
            let anchor = session.viewport.geometry.viewportPoint(
                fromContent: head,
                transform: transform
            )
            let placement = MapAdaptiveFanGeometry.verticalPlacement(
                anchor: anchor,
                itemCount: NeedleMapPinButtonType.allCases.count,
                viewport: viewportRectangle,
                preferredDirection: .top,
                // Leave exactly one 48-point button width between the two
                // needle actions while keeping both controls above the head.
                centerSpacing: MapAdaptiveFanGeometry.buttonSize.width * 2
            )
            if placement.isValid {
                MapNeedleViewportMenu(
                    session: session,
                    entryId: entryId,
                    point: point,
                    placement: placement
                )
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
    }

    private var shouldShow: Bool {
        session.mapMode == .edit
            && (session.displayMode == .master || session.displayMode == .reader)
            && session.pins.isExpandedId == nil
            && session.rooms.needleDrag.dragCoordinate == nil
    }
}

private struct MapNeedleViewportMenu: View {
    let session: MapEditorSession
    let entryId: UUID
    let point: MapNeedlePointModel
    let placement: MapAdaptiveFanPlacement

    @Namespace private var glassNamespace

    var body: some View {
        Group {
#if os(visionOS)
            buttons
#else
            GlassEffectContainer(spacing: 12) {
                buttons
            }
#endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var buttons: some View {
        ZStack(alignment: .topLeading) {
            ForEach(NeedleMapPinButtonType.allCases.enumerated(), id: \.element) { index, type in
                Button {
                    perform(type)
                } label: {
                    Label {
                        Text(type == .remove ? "Remove Point" : "Add Point", bundle: .module)
                    } icon: {
                        Image(systemName: type.systemImage)
                    }
                    .labelStyle(.iconOnly)
                    .frame(
                        width: MapAdaptiveFanGeometry.buttonSize.width,
                        height: MapAdaptiveFanGeometry.buttonSize.height
                    )
                }
                .borderLessTVBottonStyle()
                .contentShape(.circle)
                .foregroundStyle(.white)
                .background(type == .remove ? Color.red.opacity(0.8) : Color.teal.opacity(0.8), in: .circle)
                .help(
                    Text(type == .remove ? "Remove Point" : "Add Point", bundle: .module)
                )
#if !os(visionOS)
                .glassEffect(
                    .regular.tint(
                        type == .remove ? Color.red.opacity(0.8) : Color.teal.opacity(0.8)
                    ).interactive()
                )
                .glassEffectID(type.label, in: glassNamespace)
#endif
                .contentShape(.circle)
                // Keep the Liquid Glass and hit shape on the fixed 48-point
                // leaf, then move that complete leaf into viewport space.
                .position(placement.center(at: index) ?? placement.sourceAnchor)
                .zIndex(Double(index + 1))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
