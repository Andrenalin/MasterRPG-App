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

    private var orderedSnapshots: [MapRoomSnapshot] {
        let snapshots = rooms.roomNodes.filter { $0.id != excludingEntryId }.map {
            MapRoomSnapshot(path: $0.path, bounds: $0.bounds, isShown: $0.entry.isShown)
        }
        return snapshots.filter(\.isShown) + snapshots.filter { !$0.isShown }
    }

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
            drawFog(for: snapshots.filter { !$0.isShown }, in: &context)

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
                style: StrokeStyle(lineWidth: 12, lineCap: .round, lineJoin: .round)
            )
        }
        context.stroke(
            snapshot.path,
            with: .color(.green),
            style: StrokeStyle(
                lineWidth: colorSchemeContrast == .increased ? 6 : 8,
                lineCap: .round,
                lineJoin: .round,
                dash: differentiateWithoutColor && snapshot.isShown ? [16, 8] : []
            )
        )
    }

    private func drawFog(for snapshots: [MapRoomSnapshot], in context: inout GraphicsContext) {
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
            guard let drawPlan = tilePlanner.drawPlan(for: snapshot) else {
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
    let interactionTransform: GestureState<ViewportTransform?>

    var body: some View {
        if isEnabled {
            ForEach(rooms.roomNodes) { node in
                if node.id != excludingEntryId {
                    MapRoomHitTarget(
                        node: node,
                        session: session,
                        interactionTransform: interactionTransform
                    )
                }
            }
        }
    }
}

private struct MapRoomHitTarget: View {
    let node: MapRoomNode
    let session: MapEditorSession
    let interactionTransform: GestureState<ViewportTransform?>

    var body: some View {
        node.path
            .fill(.white.opacity(0.001))
            .contentShape(node.path)
#if os(visionOS)
            .hoverEffect(.highlight)
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
            .accessibilityLabel(Text(verbatim: node.entry.name))
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

struct MapRoomSnapshot {
    let path: Path
    let bounds: CGRect
    let isShown: Bool
}

/// A fog coverage plan deliberately preserves one path per hidden room.
/// Combining these paths changes overlap semantics when polygon winding differs.
struct MapFogCoveragePlan {
    let snapshots: [MapRoomSnapshot]

    func coverageDepth(at point: CGPoint) -> Int {
        snapshots.count { $0.path.contains(point) }
    }
}

struct MapFogTileDrawPlan {
    let snapshot: MapRoomSnapshot
    let columns: [CGFloat]
    let rows: [CGFloat]

    var tileCount: Int { columns.count * rows.count }
}

/// The 2D map's per-room tile budget, shared with the 3D board so both show solid fog for the
/// same rooms. See CODE_AUDIT_19 §5.18.
public enum MapFogTileBudget {
    /// Whether a room with `roomBounds` is filled with the repeated `tileRectangle` (both in
    /// canvas coordinates) rather than solid fog.
    public static func allowsTiling(roomBounds: CGRect, tileRectangle: CGRect) -> Bool {
        MapFogTilePlanner(tileRectangle: tileRectangle).tileOrigins(covering: roomBounds) != nil
    }
}

/// Plans repeated fog tiles independently for each room. The former global
/// limit made a group of otherwise inexpensive rooms lose its tile whenever
/// their aggregate count crossed the threshold.
struct MapFogTilePlanner {
    init(tileRectangle: CGRect, maximumTilesPerRoom: Int = 4_096) {
        self.tileRectangle = tileRectangle
        self.maximumTilesPerRoom = maximumTilesPerRoom
    }

    let tileRectangle: CGRect
    let maximumTilesPerRoom: Int

    func drawPlan(for snapshot: MapRoomSnapshot) -> MapFogTileDrawPlan? {
        guard let origins = tileOrigins(covering: snapshot.bounds) else { return nil }
        return MapFogTileDrawPlan(snapshot: snapshot, columns: origins.columns, rows: origins.rows)
    }

    /// The tile lattice's column and row origins covering `bounds`, or `nil` (solid fog) when
    /// the room needs more than `maximumTilesPerRoom` tiles.
    func tileOrigins(covering bounds: CGRect) -> (columns: [CGFloat], rows: [CGFloat])? {
        guard maximumTilesPerRoom > 0 else { return nil }
        let maximumOriginsPerAxis = min(maximumTilesPerRoom, 4_096)
        let columns = tileOrigins(
            minimum: bounds.minX,
            maximum: bounds.maxX,
            sourceMinimum: tileRectangle.minX,
            length: tileRectangle.width,
            maximumCount: maximumOriginsPerAxis
        )
        let rows = tileOrigins(
            minimum: bounds.minY,
            maximum: bounds.maxY,
            sourceMinimum: tileRectangle.minY,
            length: tileRectangle.height,
            maximumCount: maximumOriginsPerAxis
        )
        guard !columns.isEmpty, !rows.isEmpty else { return nil }

        let (tileCount, didOverflow) = columns.count.multipliedReportingOverflow(by: rows.count)
        guard !didOverflow, tileCount <= maximumTilesPerRoom else { return nil }
        return (columns, rows)
    }

    private func tileOrigins(
        minimum: CGFloat,
        maximum: CGFloat,
        sourceMinimum: CGFloat,
        length: CGFloat,
        maximumCount: Int
    ) -> [CGFloat] {
        guard minimum.isFinite,
              maximum.isFinite,
              maximum >= minimum,
              sourceMinimum.isFinite,
              length.isFinite,
              length > 0,
              maximumCount > 0 else { return [] }

        let first = floor((minimum - sourceMinimum) / length) * length + sourceMinimum
        let rawCount = ceil((maximum - first) / length) + 1
        guard rawCount.isFinite,
              rawCount > 0,
              rawCount <= CGFloat(maximumCount) else { return [] }

        let count = max(1, Int(rawCount))
        return (0..<count).map { first + CGFloat($0) * length }
    }
}

private enum MapRoomCanvasSymbol: Hashable {
    case fogTile
}

/// The tile is rasterized by SwiftUI once at tile resolution, then composited
/// repeatedly by the asynchronous Canvas. It keeps the selected crop aligned
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
