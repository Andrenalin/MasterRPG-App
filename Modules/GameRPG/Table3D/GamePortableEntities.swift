// @copyright André Trettin

#if os(iOS) || os(macOS)
import CoreRPG
import Foundation
import MapRPG
import RealityKit
import SwiftUI

/// The map surface used by camera-based table views. The visionOS equivalent
/// remains an `EntityEquipment` so TabletopKit can own its placement there.
@MainActor
final class Board {
    let entity: Entity

    private let imagePlane: ModelEntity

    init() {
        let maxPlaneWidth = MapTableProjection.maxPlaneWidth
        let maxPlaneDepth = MapTableProjection.maxPlaneDepth
        let boardEntity = Entity()
        boardEntity.name = "MapSurface"

        var mapMaterial = UnlitMaterial()
        mapMaterial.color = .init(tint: .white)
        let plane = ModelEntity(
            mesh: .generatePlane(width: maxPlaneWidth, depth: maxPlaneDepth),
            materials: [mapMaterial]
        )
        plane.name = "MapImagePlane"
        plane.position.y = GameMetrics.tableThickness + GameMetrics.mapSurfaceClearance
        plane.isEnabled = false
        // Hit-testable so `viewportPanGesture` (GameTableView) can target the
        // map surface directly, separately from pins and room fog. The
        // collision shape sits well *below* the plane's own Y (`Self.hitTestYOffset`,
        // clear of `RoomHitArea`'s ±0.004 box around `MapTableProjection.pinHeight`
        // — the same height this plane is placed at) so a touch over a room's
        // fog always hits the closer room volume first, never this one: an
        // earlier attempt at this gesture placed the two coincident, which
        // made the board volume randomly win room long-press/double-tap.
        plane.components.set(BoardSurfaceComponent())
        plane.components.set(InputTargetComponent())
        plane.components.set(
            CollisionComponent(shapes: [
                ShapeResource
                    .generateBox(width: maxPlaneWidth, height: Self.hitTestBoxHeight, depth: maxPlaneDepth)
                    .offsetBy(translation: SIMD3<Float>(0, Self.hitTestYOffset, 0))
            ])
        )
        boardEntity.addChild(plane)
        imagePlane = plane

        entity = boardEntity
    }

    private static let hitTestBoxHeight: Float = 0.002
    /// Local offset (relative to `imagePlane`, itself at world Y ==
    /// `MapTableProjection.pinHeight`) putting the hit-test box's whole
    /// height range below `pinHeight - 0.004` — `RoomHitArea`'s lower bound —
    /// with a clear margin.
    private static let hitTestYOffset: Float = -0.006

    func updateMap(
        image: AKImage,
        degrees: Double,
        displayConfig: DisplayConfigModel?,
        mapModel: MapModel?,
        isGameMaster: Bool,
        panOffset: CGPoint
    ) {
        let orientedSize: CGSize
        if let mapModel, mapModel.width > 0, mapModel.height > 0 {
            orientedSize = CGSize(width: mapModel.width, height: mapModel.height)
        } else {
            orientedSize = MapTableProjection.orientedImageSize(
                image.fixedSize,
                degrees: degrees
            )
        }
        guard orientedSize.width > 0, orientedSize.height > 0 else { return }

        let aspectRatio = orientedSize.width / orientedSize.height
        let planeWidth: Float
        let planeDepth: Float
        // Fit inside the (possibly non-square) `maxPlaneWidth` ×
        // `maxPlaneDepth` box preserving aspect ratio — mirrors
        // `MapTableProjection.init`'s identical fit-box math, which this
        // plane's dimensions must stay in lockstep with so pins/rooms line
        // up with the rendered texture.
        let boxAspectRatio = MapTableProjection.maxPlaneWidth / MapTableProjection.maxPlaneDepth
        if aspectRatio > Double(boxAspectRatio) {
            planeWidth = MapTableProjection.maxPlaneWidth
            planeDepth = MapTableProjection.maxPlaneWidth / Float(aspectRatio)
        } else {
            planeDepth = MapTableProjection.maxPlaneDepth
            planeWidth = MapTableProjection.maxPlaneDepth * Float(aspectRatio)
        }
        imagePlane.model?.mesh = .generatePlane(width: planeWidth, depth: planeDepth)
        imagePlane.components.set(
            CollisionComponent(shapes: [
                ShapeResource
                    .generateBox(width: planeWidth, height: Self.hitTestBoxHeight, depth: planeDepth)
                    .offsetBy(translation: SIMD3<Float>(0, Self.hitTestYOffset, 0))
            ])
        )

        guard let compositeImage = GameTableTextureRenderer.render(
            image: image,
            degrees: degrees,
            mapModel: mapModel,
            displayConfig: displayConfig,
            isGameMaster: isGameMaster,
            panOffset: panOffset
        ) else { return }

        do {
            let texture = try TextureResource(
                image: compositeImage,
                options: .init(semantic: .color)
            )
            var material = UnlitMaterial()
            material.color = .init(texture: .init(texture))
            imagePlane.model?.materials = [material]
            imagePlane.isEnabled = true
        } catch {
            var fallbackMaterial = UnlitMaterial()
            fallbackMaterial.color = .init(tint: .gray)
            imagePlane.model?.materials = [fallbackMaterial]
            imagePlane.isEnabled = true
        }

    }

    /// Clears stale texture state when no live map photo is available.
    func clearMap() {
        imagePlane.isEnabled = false
    }
}

private enum GameTableTextureRenderer {
    /// Keeps texture upload and fog composition bounded on iPhone and Mac GPUs.
    static let maximumDimension: CGFloat = 2_048

    @MainActor
    static func render(
        image: AKImage,
        degrees: Double,
        mapModel: MapModel?,
        displayConfig: DisplayConfigModel?,
        isGameMaster: Bool,
        panOffset: CGPoint
    ) -> CGImage? {
        guard let sourceImage = GameTableImage.cgImage(from: image) else { return nil }

        let sourcePixelSize = CGSize(
            width: sourceImage.width,
            height: sourceImage.height
        )
        guard sourcePixelSize.width > 0, sourcePixelSize.height > 0 else { return nil }

        let normalizedDegrees = MapTableProjection.normalizedDegrees(degrees)
        let swapsAxes = MapTableProjection.swapsAxes(for: normalizedDegrees)
        let orientedPixelSize = swapsAxes
            ? CGSize(width: sourcePixelSize.height, height: sourcePixelSize.width)
            : sourcePixelSize
        let scale = min(1, maximumDimension / max(orientedPixelSize.width, orientedPixelSize.height))
        let sourceRenderSize = CGSize(
            width: max(1, floor(sourcePixelSize.width * scale)),
            height: max(1, floor(sourcePixelSize.height * scale))
        )
        let outputSize = swapsAxes
            ? CGSize(width: sourceRenderSize.height, height: sourceRenderSize.width)
            : sourceRenderSize

        let fallbackCoordinateSize = MapTableProjection.orientedImageSize(
            image.fixedSize,
            degrees: normalizedDegrees
        )
        let coordinateSize: CGSize
        if let mapModel, mapModel.width > 0, mapModel.height > 0 {
            coordinateSize = CGSize(width: mapModel.width, height: mapModel.height)
        } else {
            coordinateSize = fallbackCoordinateSize
        }
        let focusRect = GameTableModel.boardFocusRect(
            entries: mapModel?.entries ?? [],
            imageSize: coordinateSize,
            panOffset: panOffset
        )

        let content = GameTableTextureView(
            image: image,
            sourceRenderSize: sourceRenderSize,
            outputSize: outputSize,
            coordinateSize: coordinateSize,
            focusRect: focusRect,
            degrees: normalizedDegrees,
            entries: mapModel?.entries ?? [],
            displayConfig: displayConfig,
            isGameMaster: isGameMaster
        )
        let renderer = ImageRenderer(content: content)
        renderer.scale = 1

#if os(macOS)
        guard let renderedImage = renderer.nsImage else { return sourceImage }
        var proposedRect = CGRect(origin: .zero, size: renderedImage.size)
        return renderedImage.cgImage(
            forProposedRect: &proposedRect,
            context: nil,
            hints: nil
        ) ?? sourceImage
#else
        return renderer.uiImage?.cgImage ?? sourceImage
#endif
    }
}

private struct GameTableTextureView: View {
    let image: AKImage
    let sourceRenderSize: CGSize
    let outputSize: CGSize
    let coordinateSize: CGSize
    /// The `coordinateSize`-space rect the composited image+fog is framed
    /// to — always the full map, since the 3D board never crops/zooms into
    /// a focused room. See `GameTableModel.boardFocusRect`.
    let focusRect: CGRect
    let degrees: Double
    let entries: [MapEntryModel]
    let displayConfig: DisplayConfigModel?
    let isGameMaster: Bool

    var body: some View {
        // Per-axis, matching `drawFog`'s own scaleX/scaleY below, rather than
        // assuming coordinateSize and outputSize share exactly one aspect
        // ratio (they're independently derived and only approximately equal).
        let scaleX = coordinateSize.width > 0 ? outputSize.width / coordinateSize.width : 1
        let scaleY = coordinateSize.height > 0 ? outputSize.height / coordinateSize.height : 1
        let focusOrigin = CGPoint(x: focusRect.minX * scaleX, y: focusRect.minY * scaleY)
        let focusSize = CGSize(width: focusRect.width * scaleX, height: focusRect.height * scaleY)
        let zoomScaleX = focusSize.width > 0 ? outputSize.width / focusSize.width : 1
        let zoomScaleY = focusSize.height > 0 ? outputSize.height / focusSize.height : 1

        ZStack {
            Image(akImage: image)
                .resizable()
                .frame(
                    width: sourceRenderSize.width,
                    height: sourceRenderSize.height
                )
                .rotationEffect(.degrees(degrees))

            Canvas { context, size in
                drawFog(in: &context, size: size)
            }
        }
        .frame(width: outputSize.width, height: outputSize.height, alignment: .topLeading)
        // No-ops (scale 1, offset 0) when nothing is focused — `focusRect`
        // then equals the full `coordinateSize` rect.
        .scaleEffect(x: zoomScaleX, y: zoomScaleY, anchor: .topLeading)
        .offset(x: -focusOrigin.x * zoomScaleX, y: -focusOrigin.y * zoomScaleY)
        .frame(width: outputSize.width, height: outputSize.height, alignment: .topLeading)
        .clipped()
    }

    private func drawFog(in context: inout GraphicsContext, size: CGSize) {
        guard coordinateSize.width > 0, coordinateSize.height > 0 else { return }
        let scaleX = size.width / coordinateSize.width
        let scaleY = size.height / coordinateSize.height
        let lineScale = min(scaleX, scaleY)

        for entry in entries where isGameMaster || !entry.isShown {
            guard let first = entry.coordinates.first else { continue }
            var path = Path()
            path.move(to: scaled(first, x: scaleX, y: scaleY))
            for point in entry.coordinates.dropFirst() {
                path.addLine(to: scaled(point, x: scaleX, y: scaleY))
            }
            path.closeSubpath()

            if isGameMaster {
                context.fill(
                    path,
                    with: .color(.green.opacity(entry.isShown ? 0.1 : 0.5))
                )
                context.stroke(
                    path,
                    with: .color(.green.opacity(0.8)),
                    style: StrokeStyle(
                        lineWidth: max(1, 8 * lineScale),
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
            } else if let displayConfig {
                context.fill(path, with: .color(displayConfig.color))
                if displayConfig.hasBorder {
                    context.stroke(
                        path,
                        with: .color(displayConfig.borderColor),
                        lineWidth: max(1, displayConfig.borderThickness * lineScale)
                    )
                }
            }

            // The 3D board never crops/zooms into a focused room (see
            // `GameTableModel.boardFocusRect`) — a red border marks where
            // the 2D map's own zoom is centered instead.
            if entry.focused {
                context.stroke(
                    path,
                    with: .color(.red),
                    style: StrokeStyle(lineWidth: max(1, 10 * lineScale), lineCap: .round, lineJoin: .round)
                )
            }
        }
    }

    private func scaled(_ point: CGPoint, x: CGFloat, y: CGFloat) -> CGPoint {
        CGPoint(x: point.x * x, y: point.y * y)
    }
}

#Preview("Game table texture") {
    let image = AKImage()
    let room = MapEntryModel(
        id: UUID(),
        name: "Hidden chamber",
        content: "Preview fog area.",
        coordinates: [
            CGPoint(x: 40, y: 40),
            CGPoint(x: 280, y: 40),
            CGPoint(x: 280, y: 200),
            CGPoint(x: 40, y: 200)
        ],
        isShown: false
    )
    let displayConfig = DisplayConfigModel(
        tileCoordinates: [],
        color: .black.opacity(0.72),
        border: DisplayBorderViewModel(thickness: 3, color: .blue)
    )

    GameTableTextureView(
        image: image,
        sourceRenderSize: CGSize(width: 320, height: 240),
        outputSize: CGSize(width: 320, height: 240),
        coordinateSize: CGSize(width: 320, height: 240),
        focusRect: CGRect(x: 0, y: 0, width: 320, height: 240),
        degrees: 0,
        entries: [room],
        displayConfig: displayConfig,
        isGameMaster: true
    )
}

#endif
