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

// Drawn directly with Core Graphics rather than a SwiftUI `ZStack`/`Canvas` snapshotted
// through `ImageRenderer`: the photo and the fog have genuinely different sizing rules (the
// photo must preserve its own aspect ratio; the fog must exactly fill `coordinateSize`, the
// plane's own aspect ratio — see `Board.updateMap`'s doc for why that can't move), and this
// used to size the whole raster (`outputSize`) from the photo's own pixel dimensions while
// `coordinateSize` (the map's stored width/height) sized the plane mesh — two independently
// derived values with no guarantee of sharing an aspect ratio. Whenever they didn't, the photo
// baked into that mismatched-aspect raster came out visibly stretched once mapped onto the
// mesh. A plain `CGContext`, sized to `coordinateSize` throughout with the photo fit inside it,
// removes that mismatch entirely — mirrors `GameEquipment.Board`'s visionOS equivalent.
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

        // `image.size` — not `sourceImage.width`/`.height` (the *pixel* size of whichever
        // backing representation `GameTableImage.cgImage` happened to pick, e.g. a 2x/3x
        // "Retina" `NSImage` representation on macOS) — matches the unit `MapModel.resetImage`
        // measured `coordinateSize` in (`EditController.resetImageSize` reads the same `image.size`
        // at edit time). Mixing the two here previously made the photo render at a fraction of its
        // intended size whenever the live-fetched image's pixel/point ratio wasn't 1:1.
        let sourceSize = image.size
        guard sourceSize.width > 0, sourceSize.height > 0 else { return sourceImage }

        let normalizedDegrees = MapTableProjection.normalizedDegrees(degrees)
        let orientedSize = MapTableProjection.orientedImageSize(sourceSize, degrees: normalizedDegrees)

        // `coordinateSize` is the plane mesh's own aspect ratio (see `Board.updateMap`, which
        // computes its `planeWidth`/`planeDepth` from this exact same value) — the canvas the
        // photo and fog both render into here, so neither can end up a different aspect ratio
        // than the mesh they're mapped onto.
        let coordinateSize: CGSize
        if let mapModel, mapModel.width > 0, mapModel.height > 0 {
            coordinateSize = CGSize(width: mapModel.width, height: mapModel.height)
        } else {
            coordinateSize = orientedSize
        }
        guard coordinateSize.width > 0, coordinateSize.height > 0 else { return sourceImage }

        let longestEdge = max(coordinateSize.width, coordinateSize.height)
        let renderScale = longestEdge > 0 ? min(1, maximumDimension / longestEdge) : 1
        let pixelWidth = max(1, Int((coordinateSize.width * renderScale).rounded()))
        let pixelHeight = max(1, Int((coordinateSize.height * renderScale).rounded()))

        guard let context = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return sourceImage
        }

        // Maps `coordinateSize` points onto the context's actual pixel dimensions (the two
        // differ only by `renderScale`'s GPU-budget downsampling) — a plain positive scale, so,
        // unlike the two blocks below, this permanently active base transform never needs its own
        // save/restore: it never flips or reflects anything.
        context.scaleBy(x: CGFloat(pixelWidth) / coordinateSize.width, y: CGFloat(pixelHeight) / coordinateSize.height)

        // Draw the base photo scaled to exactly fill `coordinateSize` (the plane's own aspect
        // ratio — see `Board.updateMap`'s doc) rather than fit-and-letterbox inside it:
        // `coordinateSize` and the photo's own size are kept in lockstep by `MapModel.resetImage`,
        // so the plane's fit-inside-the-table-minus-margin box
        // (`MapTableProjection.maxPlaneWidth`/`maxPlaneDepth`, already reserving space for each
        // seat's dice) is the only margin that should ever show — the photo itself should always
        // reach every edge of it. Scaled per axis (`scaleX`/`scaleY`) rather than by one uniform
        // factor so the photo still fills exactly even if the two sizes agree on aspect ratio but
        // not on absolute scale; when they also agree on aspect ratio — the normal case — the two
        // factors are equal anyway, so this never distorts the photo in practice.
        //
        // Runs in Core Graphics' native bottom-left-origin, +y-up space (rather than the
        // top-left/+y-down space `entry.coordinates` below use) deliberately: `CGContext.draw(_:in:)`
        // always maps a `CGImage`'s first (visually topmost) row to its rect's *maximum* y — the
        // correct, right-side-up result in a +y-up space, where the rect's max-y edge is the one
        // that's visually on top. Doing this inside the flipped space the fog block below uses
        // would instead put that same first row at the visually *bottom* edge, rendering the photo
        // upside down. The rotation angle is negated to compensate: a positive `degrees` here
        // needs to still turn the photo clockwise, matching what the equivalent
        // `.rotationEffect(.degrees(degrees))` on the (+y-down) 2D map does, and `context.rotate`
        // turns counterclockwise for a positive angle in a +y-up space.
        let scaleX = orientedSize.width > 0 ? coordinateSize.width / orientedSize.width : 1
        let scaleY = orientedSize.height > 0 ? coordinateSize.height / orientedSize.height : 1
        context.saveGState()
        context.translateBy(x: coordinateSize.width / 2, y: coordinateSize.height / 2)
        context.rotate(by: -CGFloat(normalizedDegrees) * .pi / 180)
        context.scaleBy(x: scaleX, y: scaleY)
        context.draw(
            sourceImage,
            in: CGRect(x: -sourceSize.width / 2, y: -sourceSize.height / 2, width: sourceSize.width, height: sourceSize.height)
        )
        context.restoreGState()

        // Draw each room entry as a fog-of-war polygon, directly in `coordinateSize` space — the
        // 3D board never crops/zooms into a focused room (only the 2D map does; see
        // `GameTableModel.boardFocusRect`), so this needs no further transform beyond matching
        // `entry.coordinates`' own top-left-origin, +y-down convention (unlike the photo above,
        // a filled/stroked path has no "first row" to invert, so this flip can't put it upside
        // down the way it would the photo).
        context.saveGState()
        context.translateBy(x: 0, y: coordinateSize.height)
        context.scaleBy(x: 1, y: -1)
        for entry in mapModel?.entries ?? [] where isGameMaster || !entry.isShown {
            guard let firstPoint = entry.coordinates.first else { continue }
            let path = CGMutablePath()
            path.move(to: firstPoint)
            for point in entry.coordinates.dropFirst() {
                path.addLine(to: point)
            }
            path.closeSubpath()

            if isGameMaster {
                context.addPath(path)
                context.setFillColor(AKColor(Color.green.opacity(entry.isShown ? 0.1 : 0.5)).cgColor)
                context.fillPath()
                context.addPath(path)
                context.setStrokeColor(AKColor(Color.green.opacity(0.8)).cgColor)
                context.setLineWidth(8)
                context.setLineCap(.round)
                context.setLineJoin(.round)
                context.strokePath()
            } else if let displayConfig {
                context.addPath(path)
                context.setFillColor(AKColor(displayConfig.color).cgColor)
                context.fillPath()
                if displayConfig.hasBorder {
                    context.addPath(path)
                    context.setStrokeColor(AKColor(displayConfig.borderColor).cgColor)
                    context.setLineWidth(displayConfig.borderThickness)
                    context.strokePath()
                }
            }

            // The 3D board never crops/zooms into a focused room (see
            // `GameTableModel.boardFocusRect`) — a red border marks where the 2D map's own zoom
            // is centered instead.
            if entry.focused {
                context.addPath(path)
                context.setStrokeColor(AKColor.red.cgColor)
                context.setLineWidth(10)
                context.setLineCap(.round)
                context.setLineJoin(.round)
                context.strokePath()
            }
        }
        context.restoreGState()

        return context.makeImage() ?? sourceImage
    }
}

#endif
