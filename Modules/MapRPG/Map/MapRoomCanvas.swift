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
    let canvasSize: CGSize
    var excludingEntryId: UUID? = nil

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    var body: some View {
        let snapshots = orderedSnapshots
        Canvas(opaque: false, colorMode: .nonLinear, rendersAsynchronously: true) { context, _ in
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
        .frame(width: canvasSize.width, height: canvasSize.height)
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
        let coordinates = displayConfig.tileCoordinates
        guard coordinates.count == 4,
              let minimumX = coordinates.map(\.x).min(),
              let maximumX = coordinates.map(\.x).max(),
              let minimumY = coordinates.map(\.y).min(),
              let maximumY = coordinates.map(\.y).max() else { return nil }
        let rectangle = CGRect(
            x: minimumX,
            y: minimumY,
            width: maximumX - minimumX,
            height: maximumY - minimumY
        )
        guard rectangle.width.isFinite,
              rectangle.height.isFinite,
              rectangle.width >= 1,
              rectangle.height >= 1 else { return nil }
        return rectangle
    }

}

struct MapActiveRoomLayer: View {
    let rooms: MapEntryViewerModel
    let displayMode: MapDisplayMode
    let displayConfig: DisplayConfigModel
    let mapImage: AKImage
    let degrees: Double
    let canvasSize: CGSize

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
        guard maximumTilesPerRoom > 0 else { return nil }
        let maximumOriginsPerAxis = min(maximumTilesPerRoom, 4_096)
        let columns = tileOrigins(
            minimum: snapshot.bounds.minX,
            maximum: snapshot.bounds.maxX,
            sourceMinimum: tileRectangle.minX,
            length: tileRectangle.width,
            maximumCount: maximumOriginsPerAxis
        )
        let rows = tileOrigins(
            minimum: snapshot.bounds.minY,
            maximum: snapshot.bounds.maxY,
            sourceMinimum: tileRectangle.minY,
            length: tileRectangle.height,
            maximumCount: maximumOriginsPerAxis
        )
        guard !columns.isEmpty, !rows.isEmpty else { return nil }

        let (tileCount, didOverflow) = columns.count.multipliedReportingOverflow(by: rows.count)
        guard !didOverflow, tileCount <= maximumTilesPerRoom else { return nil }
        return MapFogTileDrawPlan(snapshot: snapshot, columns: columns, rows: rows)
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
        canvasSize: CGSize(width: MapModel.preview.width, height: MapModel.preview.height)
    )
    .scaleEffect(0.5, anchor: .topLeading)
    .frame(width: MapModel.preview.width / 2, height: MapModel.preview.height / 2)
    .clipped()
}

#Preview("Player fog canvas") {
    let image = AKImage()

    MapActiveRoomLayer(
        rooms: MapEntryViewerModel(
            mapId: MapModel.preview.id,
            entries: MapModel.preview.entries
        ),
        displayMode: .player,
        displayConfig: MapModel.preview.displayConfig,
        mapImage: image,
        degrees: 0,
        canvasSize: CGSize(width: MapModel.preview.width, height: MapModel.preview.height)
    )
    .scaleEffect(0.5, anchor: .topLeading)
    .frame(width: MapModel.preview.width / 2, height: MapModel.preview.height / 2)
    .clipped()
}
