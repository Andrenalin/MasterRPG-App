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
                context.stroke(
                    snapshot.path,
                    with: .color(.green.opacity(0.8)),
                    style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round)
                )
            }

        case (.base, .reader):
            for snapshot in snapshots {
                context.stroke(
                    snapshot.path,
                    with: .color(.green.opacity(0.8)),
                    style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round)
                )
            }

        case (.fog, .player):
            drawFog(for: snapshots.filter { !$0.isShown }, in: &context)

        case (.base, .player), (.fog, .master), (.fog, .reader):
            break
        }
    }

    private func drawFog(for snapshots: [MapRoomSnapshot], in context: inout GraphicsContext) {
        guard !snapshots.isEmpty else { return }

        var combinedPath = Path()
        var combinedBounds = CGRect.null
        for snapshot in snapshots {
            combinedPath.addPath(snapshot.path)
            combinedBounds = combinedBounds.union(snapshot.bounds)
        }

        guard let tile = tileRectangle,
              let symbol = context.resolveSymbol(id: MapRoomCanvasSymbol.fogTile) else {
            context.fill(combinedPath, with: .color(displayConfig.color))
            return
        }

        let columns = tileOrigins(
            minimum: combinedBounds.minX,
            maximum: combinedBounds.maxX,
            sourceMinimum: tile.minX,
            length: tile.width
        )
        let rows = tileOrigins(
            minimum: combinedBounds.minY,
            maximum: combinedBounds.maxY,
            sourceMinimum: tile.minY,
            length: tile.height
        )
        guard !columns.isEmpty, !rows.isEmpty, columns.count * rows.count <= 4_096 else {
            context.fill(combinedPath, with: .color(displayConfig.color))
            return
        }

        context.drawLayer { layer in
            layer.clip(to: combinedPath)
            for x in columns {
                for y in rows {
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

    private func tileOrigins(
        minimum: CGFloat,
        maximum: CGFloat,
        sourceMinimum: CGFloat,
        length: CGFloat
    ) -> [CGFloat] {
        guard minimum.isFinite,
              maximum.isFinite,
              sourceMinimum.isFinite,
              length.isFinite,
              length > 0 else { return [] }
        let first = floor((minimum - sourceMinimum) / length) * length + sourceMinimum
        let count = max(1, Int(ceil((maximum - first) / length)) + 1)
        guard count <= 4_096 else { return [] }
        return (0..<count).map { first + CGFloat($0) * length }
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
            ForEach(rooms.roomNodes.filter { $0.id != excludingEntryId }) { node in
                MapRoomHitTarget(
                    node: node,
                    session: session,
                    interactionTransform: interactionTransform
                )
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
            .highPriorityGesture(doubleTapGesture.exclusively(before: longPressGesture))
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

private struct MapRoomSnapshot {
    let path: Path
    let bounds: CGRect
    let isShown: Bool
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
