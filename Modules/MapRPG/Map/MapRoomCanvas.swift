// @copyright André Trettin

import CoreRPG
import SwiftUI

enum MapRoomCanvasPhase: Equatable {
    case base
    case fog
}

struct MapPassiveRoomCanvas: View {
    let rooms: MapEntryViewerModel
    let displayMode: MapDisplayMode
    let displayConfig: DisplayConfigModel
    let phase: MapRoomCanvasPhase
    let mapImage: AKImage
    let degrees: Double
    /// The logical map's full content size — only used for content-space math
    /// (room bounds, the fog tile sample). Never the frame this view draws
    /// into; see `viewportSize`.
    let canvasSize: CGSize
    /// The current pan/zoom, applied inside this view's own `GraphicsContext`
    /// instead of relying on an ancestor `.scaleEffect`.
    let transform: ViewportTransform
    /// This view's own on-screen frame — the visible viewport, not the full
    /// (possibly huge) logical map. Keeping the Canvas framed and rasterized
    /// at this size, rather than at `canvasSize` and then shrunk by an
    /// ancestor `.scaleEffect`, is what keeps room/fog boundaries crisp when
    /// a large map is fitted far below its native scale (e.g. a big dungeon
    /// map on a phone). A `Canvas` is immediate-mode/bitmap content, unlike
    /// the vector-backed `Image`/`Shape` layers elsewhere in this canvas, so
    /// it is the one piece that visibly degrades under an extreme ancestor
    /// downscale — see MapEditorViewportTransformTests for the actual ratio.
    let viewportSize: CGSize
    var excludingEntryId: UUID? = nil

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    var body: some View {
        let snapshots = orderedSnapshots
        // Synchronous on purpose: an async-rendered Canvas here can skip its
        // first draw pass entirely (nothing appears until an unrelated
        // Core Animation transaction — such as the one a pinch gesture
        // produces — forces the backing layer to flush). Room visibility/fog
        // is gameplay-critical (a GM overlay or, worse, a player's
        // fog-of-war) so it must never depend on an incidental relayout to
        // draw correctly. The content here (a handful of room paths plus one
        // resolved tile symbol) is cheap enough that synchronous drawing
        // costs nothing measurable.
        Canvas(opaque: false, colorMode: .nonLinear, rendersAsynchronously: false) { context, _ in
            // Translate then scale, matching ViewportGeometry.viewportPoint's
            // `content * scale + offset` — everything drawn below stays in
            // logical map-content coordinates.
            context.translateBy(x: transform.offset.x, y: transform.offset.y)
            context.scaleBy(x: transform.scale, y: transform.scale)
            draw(snapshots: snapshots, in: &context)
        } symbols: {
            if phase == .fog,
               displayMode == .player,
               let tile = tileRectangle {
                MapFogTileSymbol(
                    image: mapImage,
                    degrees: degrees,
                    canvasSize: canvasSize,
                    tileRectangle: tile
                )
                .tag(MapRoomCanvasSymbol.fogTile)
            }
        }
        .frame(width: viewportSize.width, height: viewportSize.height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The rooms that can be seen, shown ones first. Rooms outside the visible part of the map
    /// are left out: every pan or zoom frame used to draw all of them, which on a hex map is
    /// up to 20,000 cells, each with its own clipped layer in the fog. One pass instead of two
    /// maps and two filters. See CODE_AUDIT_21 §7.8.
    private var orderedSnapshots: [MapRoomSnapshot] {
        let visible = Self.visibleContentRect(transform: transform, viewportSize: viewportSize)
        var shown: [MapRoomSnapshot] = []
        var hidden: [MapRoomSnapshot] = []
        for node in rooms.roomNodes where node.id != excludingEntryId && node.bounds.intersects(visible) {
            let snapshot = MapRoomSnapshot(path: node.path, bounds: node.bounds, isShown: node.entry.isShown)
            if snapshot.isShown {
                shown.append(snapshot)
            } else {
                hidden.append(snapshot)
            }
        }
        return shown + hidden
    }

    /// The part of the map content the viewport shows, grown by the widest boundary stroke so a
    /// room just outside still draws the half of its outline that reaches in. The whole plane
    /// for a transform that cannot be inverted.
    static func visibleContentRect(transform: ViewportTransform, viewportSize: CGSize) -> CGRect {
        guard transform.scale.isFinite, transform.scale > 0,
              transform.offset.x.isFinite, transform.offset.y.isFinite else { return .infinite }
        return CGRect(
            x: -transform.offset.x / transform.scale,
            y: -transform.offset.y / transform.scale,
            width: viewportSize.width / transform.scale,
            height: viewportSize.height / transform.scale
        ).insetBy(dx: -boundaryStrokeMargin, dy: -boundaryStrokeMargin)
    }

    /// Half of the widest boundary stroke (12 in increased contrast), with room to spare.
    private static let boundaryStrokeMargin: CGFloat = 16

    private func draw(snapshots: [MapRoomSnapshot], in context: inout GraphicsContext) {
        switch (phase, displayMode) {
        case (.base, .master):
            for snapshot in snapshots {
                context.fill(
                    snapshot.path,
                    with: .color(.green.opacity(snapshot.isShown ? 0.1 : 0.5))
                )
                drawBoundary(for: snapshot, in: &context)
            }

        case (.base, .reader):
            for snapshot in snapshots {
                drawBoundary(for: snapshot, in: &context)
            }

        case (.fog, .player):
            drawFog(for: snapshots.filter { !$0.isShown }, visible: Self.visibleContentRect(transform: transform, viewportSize: viewportSize), in: &context)

        case (.base, .player), (.fog, .master), (.fog, .reader):
            break
        }
    }

    private func drawBoundary(
        for snapshot: MapRoomSnapshot,
        in context: inout GraphicsContext
    ) {
        if colorSchemeContrast == .increased {
            context.stroke(
                snapshot.path,
                with: .color(.primary.opacity(0.9)),
                style: StrokeStyle(lineWidth: MapRoomStroke.increasedContrastHalo, lineCap: .round, lineJoin: .round)
            )
        }
        context.stroke(
            snapshot.path,
            with: .color(.green),
            style: StrokeStyle(
                lineWidth: colorSchemeContrast == .increased ? MapRoomStroke.increasedContrastBorder : MapRoomStroke.border,
                lineCap: .round,
                lineJoin: .round,
                dash: differentiateWithoutColor && snapshot.isShown ? [16, 8] : []
            )
        )
    }

    private func drawFog(for snapshots: [MapRoomSnapshot], visible: CGRect, in context: inout GraphicsContext) {
        guard !snapshots.isEmpty else { return }

        let coveragePlan = MapFogCoveragePlan(snapshots: snapshots)

        guard let tile = tileRectangle,
              let symbol = context.resolveSymbol(id: MapRoomCanvasSymbol.fogTile) else {
            drawSolidFog(coveragePlan, in: &context)
            return
        }

        let tilePlanner = MapFogTilePlanner(tileRectangle: tile)

        // Keep every room in its own source-over layer. A compound path can
        // cancel where polygons use opposite winding, exposing the base map,
        // and it also flattens the intended coverage in overlapping rooms.
        for snapshot in coveragePlan.snapshots {
            // A pathological room must not disable the selected tile for every
            // other room. Fall back only for the room that cannot be planned.
            guard let drawPlan = tilePlanner.drawPlan(for: snapshot, visibleRect: visible) else {
                context.fill(snapshot.path, with: .color(displayConfig.color))
                continue
            }
            context.drawLayer { layer in
                layer.clip(to: drawPlan.snapshot.path)
                for x in drawPlan.columns {
                    for y in drawPlan.rows {
                        layer.draw(
                            symbol,
                            in: CGRect(
                                x: x,
                                y: y,
                                width: tile.width,
                                height: tile.height
                            )
                        )
                    }
                }
            }
        }
    }

    private func drawSolidFog(
        _ coveragePlan: MapFogCoveragePlan,
        in context: inout GraphicsContext
    ) {
        for snapshot in coveragePlan.snapshots {
            context.fill(snapshot.path, with: .color(displayConfig.color))
        }
    }

    private var tileRectangle: CGRect? {
        displayConfig.fogTileRectangle
    }

}

struct MapActiveRoomLayer: View {
    let rooms: MapEntryViewerModel
    let displayMode: MapDisplayMode
    let displayConfig: DisplayConfigModel
    let mapImage: AKImage
    let degrees: Double
    let canvasSize: CGSize
    let transform: ViewportTransform
    let viewportSize: CGSize

    var body: some View {
        if !rooms.roomNodes.isEmpty {
            MapPassiveRoomCanvas(
                rooms: rooms,
                displayMode: displayMode,
                displayConfig: displayConfig,
                phase: displayMode == .player ? .fog : .base,
                mapImage: mapImage,
                degrees: degrees,
                canvasSize: canvasSize,
                transform: transform,
                viewportSize: viewportSize,
                excludingEntryId: nil
            )
        }
    }
}

struct MapRoomHitLayer: View {
    let rooms: MapEntryViewerModel
    let session: MapEditorSession
    let isEnabled: Bool
    var excludingEntryId: UUID? = nil
    /// The part of the map content whose rooms get a hit target (see `hitCullingRect`).
    /// `.infinite` keeps a target for every room.
    var visibleContentRect: CGRect = .infinite
    let interactionTransform: GestureState<ViewportTransform?>

    var body: some View {
        if isEnabled {
            ForEach(visibleNodes) { node in
                MapRoomHitTarget(
                    node: node,
                    session: session,
                    interactionTransform: interactionTransform
                )
            }
        }
    }

    /// One gesture view per room used to exist for all of them, up to 20,000 on a hex map.
    /// See CODE_AUDIT_26 §7.11.
    private var visibleNodes: [MapRoomNode] {
        rooms.roomNodes.filter { $0.id != excludingEntryId && $0.bounds.intersects(visibleContentRect) }
    }

    /// The visible content rect snapped outward to steps of half its size, plus one step on every
    /// side: it stays the same while the map is panned a little, so the layer does not rebuild its
    /// targets on every frame of a pan, and a room that scrolls into view already has its target.
    static func hitCullingRect(transform: ViewportTransform, viewportSize: CGSize) -> CGRect {
        let visible = MapPassiveRoomCanvas.visibleContentRect(transform: transform, viewportSize: viewportSize)
        let step = max(visible.width, visible.height) / 2
        guard !visible.isInfinite, step.isFinite, step > 0 else { return .infinite }
        let minX = floor(visible.minX / step) * step - step
        let minY = floor(visible.minY / step) * step - step
        let maxX = ceil(visible.maxX / step) * step + step
        let maxY = ceil(visible.maxY / step) * step + step
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

private struct MapRoomHitTarget: View {
    /// An unnamed room or a hex cell is not silent for VoiceOver. See CODE_AUDIT_29 §8.4.
    static func accessibilityLabel(for entry: MapEntryModel) -> Text {
        let name = entry.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { return Text(verbatim: name) }
        return entry.isHexGrid ? Text("Hex cell", bundle: .module) : Text("Unnamed room", bundle: .module)
    }

    let node: MapRoomNode
    let session: MapEditorSession
    let interactionTransform: GestureState<ViewportTransform?>
#if os(visionOS)
    @Namespace private var hoverNamespace
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
#endif

    var body: some View {
        node.path
            .fill(.white.opacity(0.001))
            .contentShape(node.path)
#if os(visionOS)
            // Custom look-at highlight instead of the system one: the room's green border
            // (drawn by the canvas) turns red while the person looks at the room.
            .contentShape(.hoverEffect, node.path)
            .overlay {
                node.path
                    .stroke(
                        .red,
                        style: StrokeStyle(
                            lineWidth: colorSchemeContrast == .increased ? MapRoomStroke.increasedContrastBorder : MapRoomStroke.border,
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
                    .hoverEffect(in: HoverEffectGroup(hoverNamespace)) { effect, isActive, _ in
                        effect.opacity(isActive ? 1 : 0)
                    }
            }
            .hoverEffectGroup(HoverEffectGroup(hoverNamespace))
#endif
            .highPriorityGesture(
                doubleTapGesture.exclusively(before: longPressGesture)
            )
            .modifier(
                MapViewportGestureModifier(
                    session: session,
                    interactionTransform: interactionTransform,
                    isEnabled: true
                )
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Self.accessibilityLabel(for: node.entry))
            .accessibilityValue(
                node.entry.isShown
                    ? Text("Visible to Players", bundle: .module)
                    : Text("Hidden from Players", bundle: .module)
            )
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(named: Text("Toggle Player Visibility", bundle: .module)) {
                session.route(.toggleRoomVisibility(node.id))
            }
            .accessibilityAction(named: Text("Focus Map Area", bundle: .module)) {
                session.route(.toggleRoomFocus(node.id))
            }
    }

    private var doubleTapGesture: some Gesture {
        TapGesture(count: 2).onEnded {
            session.route(.toggleRoomVisibility(node.id))
        }
    }

    private var longPressGesture: some Gesture {
        LongPressGesture().onEnded { _ in
            session.route(.toggleRoomFocus(node.id))
        }
    }
}

struct MapOrientedImage: View {
    let image: AKImage
    let degrees: Double
    let canvasSize: CGSize

    private var originalSize: CGSize { image.fixedSize }
    private var rotatedSize: CGSize {
        ViewportGeometry.rotatedContentSize(originalSize, rotationDegrees: degrees)
    }

    private var horizontalScale: CGFloat {
        guard rotatedSize.width > 0 else { return 1 }
        return canvasSize.width / rotatedSize.width
    }

    private var verticalScale: CGFloat {
        guard rotatedSize.height > 0 else { return 1 }
        return canvasSize.height / rotatedSize.height
    }

    var body: some View {
        Image(akImage: image)
            .resizable()
            .frame(width: originalSize.width, height: originalSize.height)
            .rotationEffect(.degrees(ViewportGeometry.normalize(rotationDegrees: degrees)))
            .frame(width: rotatedSize.width, height: rotatedSize.height)
            .scaleEffect(x: horizontalScale, y: verticalScale)
            .frame(width: canvasSize.width, height: canvasSize.height)
    }
}

/// The room border widths in map points. See CODE_AUDIT_29 §9.10.
private enum MapRoomStroke {
    static let border: CGFloat = 8
    static let increasedContrastBorder: CGFloat = 6
    /// The dark halo drawn under the border in increased contrast.
    static let increasedContrastHalo: CGFloat = 12
}

private enum MapRoomCanvasSymbol: Hashable {
    case fogTile
}

/// The tile is rasterized by SwiftUI once at tile resolution, then composited
/// repeatedly by the Canvas (which renders synchronously). It keeps the selected crop aligned
/// with the same oriented base image without an ImageRenderer-generated cover.
private struct MapFogTileSymbol: View {
    let image: AKImage
    let degrees: Double
    let canvasSize: CGSize
    let tileRectangle: CGRect

    var body: some View {
        ZStack(alignment: .topLeading) {
            MapOrientedImage(image: image, degrees: degrees, canvasSize: canvasSize)
                .offset(x: -tileRectangle.minX, y: -tileRectangle.minY)
        }
        .frame(
            width: tileRectangle.width,
            height: tileRectangle.height,
            alignment: .topLeading
        )
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

#Preview("Master room canvas") {
    let image = AKImage()
    let viewportSize = CGSize(width: MapModel.preview.width / 2, height: MapModel.preview.height / 2)

    MapPassiveRoomCanvas(
        rooms: MapEntryViewerModel(
            mapId: MapModel.preview.id,
            entries: MapModel.preview.entries
        ),
        displayMode: .master,
        displayConfig: MapModel.preview.displayConfig,
        phase: .base,
        mapImage: image,
        degrees: 0,
        canvasSize: CGSize(width: MapModel.preview.width, height: MapModel.preview.height),
        transform: ViewportTransform(scale: 0.5),
        viewportSize: viewportSize
    )
    .frame(width: viewportSize.width, height: viewportSize.height)
    .clipped()
}

#Preview("Player fog canvas") {
    let image = AKImage()
    let viewportSize = CGSize(width: MapModel.preview.width / 2, height: MapModel.preview.height / 2)

    MapActiveRoomLayer(
        rooms: MapEntryViewerModel(
            mapId: MapModel.preview.id,
            entries: MapModel.preview.entries
        ),
        displayMode: .player,
        displayConfig: MapModel.preview.displayConfig,
        mapImage: image,
        degrees: 0,
        canvasSize: CGSize(width: MapModel.preview.width, height: MapModel.preview.height),
        transform: ViewportTransform(scale: 0.5),
        viewportSize: viewportSize
    )
    .frame(width: viewportSize.width, height: viewportSize.height)
    .clipped()
}
