// @copyright André Trettin

#if os(iOS) || os(macOS) || os(visionOS)
import CoreGraphics
import CoreRPG
import Foundation
import MapRPG
import RealityKit
import SwiftUI
import os.log

/// The map surface shared by every platform's table: a thin image plane resting on the tabletop.
/// It deliberately isn't TabletopKit equipment — TabletopKit rests equipment against its centered
/// table shape, while this scene's generated table uses its bottom as y = 0 — so pins, rooms and
/// the board all live in one bottom-origin coordinate space.
@MainActor
final class Board {
    let entity: Entity

    private let imagePlane: ModelEntity

    init() {
        let boardEntity = Entity()
        boardEntity.name = "MapSurface"

        var mapMaterial = UnlitMaterial()
        mapMaterial.color = .init(tint: .white)
        let plane = ModelEntity(
            mesh: .generatePlane(width: MapTableProjection.maxPlaneWidth, depth: MapTableProjection.maxPlaneDepth),
            materials: [mapMaterial]
        )
        plane.name = "MapImagePlane"
        plane.position.y = GameMetrics.tableThickness + GameMetrics.mapSurfaceClearance
        plane.isEnabled = false
        // Hit-testable so the board-drag gesture can target the map surface separately from pins
        // and room fog. The collision shape sits well *below* the plane's own Y so a touch over a
        // room's fog always hits the closer room volume first; coincident volumes made the board
        // randomly win room long-press/double-tap.
        plane.components.set(BoardSurfaceComponent())
        plane.components.set(InputTargetComponent())
        plane.components.set(Self.hitTestCollision(width: MapTableProjection.maxPlaneWidth, depth: MapTableProjection.maxPlaneDepth))
        boardEntity.addChild(plane)
        imagePlane = plane
        entity = boardEntity
    }

    private static let hitTestBoxHeight: Float = 0.002

    private static func hitTestCollision(width: Float, depth: Float) -> CollisionComponent {
        CollisionComponent(shapes: [
            ShapeResource
                .generateBox(width: width, height: hitTestBoxHeight, depth: depth)
                .offsetBy(translation: SIMD3<Float>(0, GameMetrics.boardHitTestYOffset, 0))
        ])
    }

    /// Renders the map photo with its fog-of-war and applies it to the board.
    ///
    /// The Core Graphics composite runs off the main actor; only the mesh/texture application
    /// happens here. Returns `true` when the board now shows this render, `false` when the request
    /// was cancelled, superseded (`shouldApply`) or nothing could be rendered — callers must not record the render as applied
    /// in that case. A failed render hides the plane rather than falling back to the raw photo,
    /// which would show hidden rooms to players.
    @discardableResult
    func updateMap(
        image: AKImage,
        degrees: Double,
        mapModel: MapModel,
        isGameMaster: Bool,
        shouldApply: @MainActor () -> Bool = { true }
    ) async -> Bool {
        guard let input = BoardTextureInput(
            image: image,
            degrees: degrees,
            mapModel: mapModel,
            isGameMaster: isGameMaster
        ) else {
            Logger.gameTable.error("Failed to snapshot the current photo for the board texture")
            clearMap()
            return false
        }

        Logger.gameTable.debug("Board texture input: photo \(input.image.width, privacy: .public)x\(input.image.height, privacy: .public) px, size \(input.sourceSize.width, privacy: .public)x\(input.sourceSize.height, privacy: .public), degrees \(input.degrees, privacy: .public), canvas \(input.coordinateSize.width, privacy: .public)x\(input.coordinateSize.height, privacy: .public)")
        let compositeImage = await BoardTextureRenderer.render(input)
        guard !Task.isCancelled, shouldApply() else { return false }
        guard let compositeImage else {
            Logger.gameTable.error("Failed to composite the board texture")
            clearMap()
            return false
        }

        var material = UnlitMaterial()
        do {
            let texture = try await TextureResource(image: compositeImage, options: .init(semantic: .color, mipmapsMode: .allocateAndGenerateAll))
            material.color = .init(texture: .init(texture))
        } catch {
            Logger.gameTable.error(
                "Failed to create the board texture: \(error.localizedDescription, privacy: .public)"
            )
            material.color = .init(tint: .gray)
        }
        // The texture upload suspended too: apply only if nothing newer started meanwhile.
        guard !Task.isCancelled, shouldApply() else { return false }

        let plane = MapTableProjection(
            imageSize: input.coordinateSize,
            planeAspectRatio: input.displaySize.width / input.displaySize.height
        )
        imagePlane.model?.mesh = .generatePlane(width: plane.planeWidth, depth: plane.planeDepth)
        imagePlane.components.set(Self.hitTestCollision(width: plane.planeWidth, depth: plane.planeDepth))
        imagePlane.model?.materials = [material]
        imagePlane.isEnabled = true
        return true
    }

    /// Describes the map for VoiceOver. The game master hears the map's name and how many rooms are
    /// still hidden; a player only hears a generic label, since both would reveal what the fog hides.
    func updateAccessibility(gameMasterSummary: (name: String, hiddenRooms: Int, rooms: Int)?) {
        var accessibility = AccessibilityComponent()
        accessibility.isAccessibilityElement = true
        if let summary = gameMasterSummary {
            accessibility.label = LocalizedStringResource("Map \(summary.name)", bundle: .module)
            accessibility.value = LocalizedStringResource("\(summary.hiddenRooms) of \(summary.rooms) rooms hidden", bundle: .module)
        } else {
            accessibility.label = LocalizedStringResource("Game map", bundle: .module)
        }
        imagePlane.components.set(accessibility)
    }

    /// Hides the board when no map photo is available.
    func clearMap() {
        imagePlane.isEnabled = false
    }
}

/// Immutable snapshot of everything the board texture depends on, captured on the main actor so
/// the composite can run elsewhere. `CGImage`/`CGColor` are immutable, so sharing them is safe.
struct BoardTextureInput: @unchecked Sendable {
    struct Room {
        let coordinates: [CGPoint]
        let isShown: Bool
        let isFocused: Bool
    }

    struct PlayerFog {
        let fill: CGColor
        let border: CGColor?
        let borderThickness: CGFloat
    }

    let image: CGImage
    /// The photo's size in the map's own unit (`image.size`), which is what `MapModel.width/height` was measured in.
    let sourceSize: CGSize
    let degrees: Double
    /// The coordinate space room polygons (and pins) are stored in.
    let coordinateSize: CGSize
    /// The shape of the drawn texture and the plane: the photo's own aspect ratio, which can differ
    /// from `coordinateSize` when the map's stored size is stale. Room polygons are stretched from
    /// the canvas onto it, the same way the 2D map stretches the photo over the canvas.
    let displaySize: CGSize
    let rooms: [Room]
    let isGameMaster: Bool
    let playerFog: PlayerFog
    let gameMasterShownFill: CGColor
    let gameMasterHiddenFill: CGColor
    let gameMasterStroke: CGColor
    let focusStroke: CGColor

    @MainActor
    init?(image: AKImage, degrees: Double, mapModel: MapModel, isGameMaster: Bool) {
        // `image.size` — not the CGImage's pixel size — matches the unit `MapModel.resetImage`
        // measured the stored width/height in; mixing the two rendered the photo at a fraction of
        // its size on Retina `NSImage`s.
        guard image.size.width > 0, image.size.height > 0 else { return nil }
        let normalizedDegrees = MapTableProjection.normalizedDegrees(degrees)
        // The same canvas the 2D map resolves, so rooms and pins land where they do in 2D.
        guard let coordinateSize = MapTableProjection.canvasSize(
            map: mapModel,
            image: image,
            degrees: normalizedDegrees
        ), coordinateSize.width > 0, coordinateSize.height > 0,
              let cgImage = GameTableImage.cgImage(from: image) else { return nil }

        let displayConfig = mapModel.displayConfig
        self.image = cgImage
        self.sourceSize = image.size
        self.degrees = normalizedDegrees
        self.coordinateSize = coordinateSize
        let displayAspect = MapTableProjection.planeAspectRatio(
            photoSize: image.size,
            degrees: normalizedDegrees,
            canvasSize: coordinateSize
        )
        self.displaySize = CGSize(width: displayAspect, height: 1)
        self.isGameMaster = isGameMaster
        self.rooms = mapModel.entries
            .filter { isGameMaster || !$0.isShown }
            .map { Room(coordinates: $0.coordinates, isShown: $0.isShown, isFocused: $0.focused) }
        self.playerFog = PlayerFog(
            fill: Self.cgColor(displayConfig.color),
            border: displayConfig.hasBorder ? Self.cgColor(displayConfig.borderColor) : nil,
            borderThickness: displayConfig.borderThickness
        )
        self.gameMasterShownFill = Self.cgColor(Color.green.opacity(0.1))
        self.gameMasterHiddenFill = Self.cgColor(Color.green.opacity(0.5))
        self.gameMasterStroke = Self.cgColor(Color.green.opacity(0.8))
        self.focusStroke = Self.cgColor(.red)
    }

    /// The one place SwiftUI colours become platform colours, so resolution is consistent.
    @MainActor
    private static func cgColor(_ color: Color) -> CGColor {
        AKColor(color).cgColor
    }
}

/// Composites the map photo with its fog-of-war, drawn directly with Core Graphics rather than a
/// SwiftUI stack snapshotted through `ImageRenderer`: the photo and the fog have different sizing
/// rules (the photo keeps its aspect ratio, the fog exactly fills the plane's), and nested SwiftUI
/// frames repeatedly ended up subtly misaligned. Each layer is drawn against an explicit rect.
enum BoardTextureRenderer {
    /// Keeps texture upload and fog composition within a conservative GPU budget.
    static let maximumDimension: CGFloat = 2_048
    private static let gameMasterStrokeWidth: CGFloat = 8
    private static let focusStrokeWidth: CGFloat = 10

    @concurrent
    static func render(_ input: BoardTextureInput) async -> CGImage? {
        let canvas = input.coordinateSize
        let orientedSize = MapTableProjection.orientedImageSize(input.sourceSize, degrees: input.degrees)

        // The texture has the photo's own shape (`displaySize`), not the stored canvas': the photo is
        // never stretched. Its pixel budget follows the photo's own resolution (never upscaling it,
        // never exceeding the GPU cap), so a high-resolution photo whose stored map size is small
        // isn't squeezed into a tiny texture.
        let displayAspect = input.displaySize.width / input.displaySize.height
        let photoLongSide = CGFloat(max(input.image.width, input.image.height))
        let targetLongSide = min(maximumDimension, max(1, photoLongSide))
        let pixelWidth = max(1, Int((displayAspect >= 1 ? targetLongSide : targetLongSide * displayAspect).rounded()))
        let pixelHeight = max(1, Int((displayAspect >= 1 ? targetLongSide / displayAspect : targetLongSide).rounded()))

        guard let context = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        let pixelSize = CGSize(width: pixelWidth, height: pixelHeight)

        // The photo is drawn in pixel space, scaled uniformly to fit: it fills the texture exactly
        // (its shape *is* the texture's) except for a rotation that isn't a multiple of 90°, where
        // the canvas is a bounding box and the remainder stays dark. Drawn in Core Graphics' native
        // bottom-left-origin space because `CGContext.draw` maps a `CGImage`'s first row to the
        // rect's max y — right side up here, upside down in the flipped space the fog uses. The
        // angle is negated so a positive `degrees` still turns the photo clockwise like
        // `.rotationEffect` on the 2D map.
        let fitScale = orientedSize.width > 0 && orientedSize.height > 0
            ? min(pixelSize.width / orientedSize.width, pixelSize.height / orientedSize.height)
            : 1
        context.setFillColor(CGColor(gray: 0.1, alpha: 1))
        context.fill(CGRect(origin: .zero, size: pixelSize))
        context.interpolationQuality = .high
        context.saveGState()
        context.translateBy(x: pixelSize.width / 2, y: pixelSize.height / 2)
        context.rotate(by: -CGFloat(input.degrees) * .pi / 180)
        context.scaleBy(x: fitScale, y: fitScale)
        context.draw(
            input.image,
            in: CGRect(
                x: -input.sourceSize.width / 2,
                y: -input.sourceSize.height / 2,
                width: input.sourceSize.width,
                height: input.sourceSize.height
            )
        )
        context.restoreGState()

        // Maps canvas points (where the rooms live) onto the texture's pixels — per axis, so rooms
        // stay on the same spot of the picture even when the canvas' shape differs from the photo's.
        context.scaleBy(x: pixelSize.width / canvas.width, y: pixelSize.height / canvas.height)

        guard !Task.isCancelled else { return nil }

        // Room polygons use `entry.coordinates`' top-left-origin, +y-down convention. The 3D board
        // never crops into a focused room; a red border marks the focus instead.
        context.saveGState()
        context.translateBy(x: 0, y: canvas.height)
        context.scaleBy(x: 1, y: -1)
        for room in input.rooms {
            guard let firstPoint = room.coordinates.first else { continue }
            let path = CGMutablePath()
            path.move(to: firstPoint)
            for point in room.coordinates.dropFirst() {
                path.addLine(to: point)
            }
            path.closeSubpath()

            if input.isGameMaster {
                // Transparent green with a border — lighter for a shown room, more solid for one
                // still hidden from players.
                context.addPath(path)
                context.setFillColor(room.isShown ? input.gameMasterShownFill : input.gameMasterHiddenFill)
                context.fillPath()
                context.addPath(path)
                context.setStrokeColor(input.gameMasterStroke)
                context.setLineWidth(gameMasterStrokeWidth)
                context.setLineCap(.round)
                context.setLineJoin(.round)
                context.strokePath()
            } else {
                // Players only ever get the hidden rooms (see `BoardTextureInput`), drawn as solid fog.
                context.addPath(path)
                context.setFillColor(input.playerFog.fill)
                context.fillPath()
                if let border = input.playerFog.border {
                    context.addPath(path)
                    context.setStrokeColor(border)
                    context.setLineWidth(input.playerFog.borderThickness)
                    context.strokePath()
                }
            }

            if room.isFocused {
                context.addPath(path)
                context.setStrokeColor(input.focusStroke)
                context.setLineWidth(focusStrokeWidth)
                context.setLineCap(.round)
                context.setLineJoin(.round)
                context.strokePath()
            }
        }
        context.restoreGState()

        return context.makeImage()
    }
}
#endif
