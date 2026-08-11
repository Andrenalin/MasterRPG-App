// @copyright André Trettin

#if os(iOS) || os(macOS)
import CoreRPG
import Foundation
import MapRPG
import RealityKit
import SwiftUI

#if os(macOS)
import AppKit
private typealias GameTablePlatformColor = NSColor
#else
import UIKit
private typealias GameTablePlatformColor = UIColor
#endif

/// The map surface used by camera-based table views. The visionOS equivalent
/// remains an `EntityEquipment` so TabletopKit can own its placement there.
@MainActor
final class Board {
    let entity: Entity

    private let imagePlane: ModelEntity
    private let mapSize = MapTableProjection.mapSize

    init() {
        let boardEntity = Entity()
        boardEntity.name = "MapSurface"

        var mapMaterial = UnlitMaterial()
        mapMaterial.color = .init(tint: .white)
        let plane = ModelEntity(
            mesh: .generatePlane(width: mapSize, depth: mapSize),
            materials: [mapMaterial]
        )
        plane.name = "MapImagePlane"
        plane.position.y = GameMetrics.tableThickness + GameMetrics.mapSurfaceClearance
        plane.isEnabled = false
        boardEntity.addChild(plane)
        imagePlane = plane

        entity = boardEntity
    }

    func updateMap(
        image: AKImage,
        degrees: Double,
        displayConfig: DisplayConfigModel?,
        mapModel: MapModel?,
        isGameMaster: Bool
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
        if aspectRatio > 1 {
            planeWidth = mapSize
            planeDepth = mapSize / Float(aspectRatio)
        } else {
            planeDepth = mapSize
            planeWidth = mapSize * Float(aspectRatio)
        }
        imagePlane.model?.mesh = .generatePlane(width: planeWidth, depth: planeDepth)

        guard let compositeImage = GameTableTextureRenderer.render(
            image: image,
            degrees: degrees,
            mapModel: mapModel,
            displayConfig: displayConfig,
            isGameMaster: isGameMaster
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
        isGameMaster: Bool
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

        let content = GameTableTextureView(
            image: image,
            sourceRenderSize: sourceRenderSize,
            outputSize: outputSize,
            coordinateSize: coordinateSize,
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
    let degrees: Double
    let entries: [MapEntryModel]
    let displayConfig: DisplayConfigModel?
    let isGameMaster: Bool

    var body: some View {
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
        .frame(width: outputSize.width, height: outputSize.height)
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
        degrees: 0,
        entries: [room],
        displayConfig: displayConfig,
        isGameMaster: true
    )
}

/// Identifies a map token for entity-targeted gestures.
struct PinComponent: Component {
    let pinId: UUID
}

/// Identifies a room's fog hit-test volume for entity-targeted gestures.
struct RoomComponent: Component {
    let roomId: UUID
}

@MainActor
final class PinPawn {
    let pinId: UUID
    let entity: Entity
    var loadedPhotoId: UUID?

    private let baseModel: ModelEntity
    private let photoPlane: ModelEntity
    private let highlightModel: ModelEntity
    private let deathMarkModels: [ModelEntity]
    private var currentSize: MapPinModel.MapPinSize
    private var currentPointsToMeters: Float

    init(pin: MapPinModel, pointsToMeters: Float) {
        pinId = pin.id
        currentSize = pin.size
        currentPointsToMeters = pointsToMeters
        let radius = Self.radius(for: pin.size, pointsToMeters: pointsToMeters)
        let diameter = radius * 1.8

        var baseMaterial = UnlitMaterial()
        baseMaterial.color = .init(tint: GameTablePlatformColor(pin.color))
        baseModel = ModelEntity(
            mesh: .generateCylinder(height: 0.005, radius: radius),
            materials: [baseMaterial]
        )
        baseModel.name = "PinBase"

        var highlightMaterial = UnlitMaterial()
        highlightMaterial.color = .init(tint: .systemRed)
        let highlight = ModelEntity(
            mesh: .generateCylinder(height: 0.001, radius: radius * 1.18),
            materials: [highlightMaterial]
        )
        highlight.name = "PinHighlightRing"
        highlight.position.y = -0.002
        highlight.isEnabled = false
        highlightModel = highlight

        var photoMaterial = UnlitMaterial()
        photoMaterial.color = .init(tint: GameTablePlatformColor(pin.color))
        photoPlane = ModelEntity(
            mesh: .generatePlane(
                width: diameter,
                depth: diameter,
                cornerRadius: diameter / 2
            ),
            materials: [photoMaterial]
        )
        photoPlane.name = "PinPhotoPlane"
        photoPlane.position.y = 0.004

        var deathMaterial = UnlitMaterial()
        deathMaterial.color = .init(tint: .white)
        let deathBarLength = diameter * 0.72
        let deathBarThickness = max(diameter * 0.10, 0.0015)
        let firstDeathBar = ModelEntity(
            mesh: .generateBox(
                width: deathBarLength,
                height: 0.001,
                depth: deathBarThickness
            ),
            materials: [deathMaterial]
        )
        firstDeathBar.name = "PinDeathMarkFirstBar"
        firstDeathBar.position.y = 0.006
        firstDeathBar.orientation = simd_quatf(
            angle: .pi / 4,
            axis: SIMD3<Float>(0, 1, 0)
        )
        firstDeathBar.isEnabled = false

        let secondDeathBar = ModelEntity(
            mesh: .generateBox(
                width: deathBarLength,
                height: 0.001,
                depth: deathBarThickness
            ),
            materials: [deathMaterial]
        )
        secondDeathBar.name = "PinDeathMarkSecondBar"
        secondDeathBar.position.y = 0.006
        secondDeathBar.orientation = simd_quatf(
            angle: -.pi / 4,
            axis: SIMD3<Float>(0, 1, 0)
        )
        secondDeathBar.isEnabled = false
        deathMarkModels = [firstDeathBar, secondDeathBar]

        let pinEntity = Entity()
        pinEntity.name = "Pin-\(pin.name)"
        pinEntity.addChild(highlight)
        pinEntity.addChild(baseModel)
        pinEntity.addChild(photoPlane)
        pinEntity.addChild(firstDeathBar)
        pinEntity.addChild(secondDeathBar)
        pinEntity.components.set(PinComponent(pinId: pin.id))
        pinEntity.components.set(InputTargetComponent())
        pinEntity.components.set(
            CollisionComponent(
                shapes: [
                    .generateBox(
                        width: diameter,
                        height: 0.02,
                        depth: diameter
                    )
                ]
            )
        )
        pinEntity.components.set(HoverEffectComponent())
        var accessibility = AccessibilityComponent()
        accessibility.isAccessibilityElement = true
        accessibility.label = LocalizedStringResource("Map pin \(pin.name)", bundle: .module)
        accessibility.value = Self.accessibilityValue(for: pin)
        accessibility.systemActions = .activate
        accessibility.customActions = [
            LocalizedStringResource("Toggle Pin Zoom", bundle: .module)
        ]
        pinEntity.components.set(accessibility)
        entity = pinEntity
    }

    func update(
        pin: MapPinModel,
        position: SIMD3<Float>,
        hiddenForMaster: Bool,
        activeAttackerPinId: UUID? = nil,
        pointsToMeters: Float
    ) {
        entity.position = position
        entity.scale = SIMD3<Float>(repeating: pin.isZoom ? 4 : 1)
        if pin.size != currentSize || pointsToMeters != currentPointsToMeters {
            currentSize = pin.size
            currentPointsToMeters = pointsToMeters
            applySize(pin.size, pointsToMeters: pointsToMeters)
        }

        var baseMaterial = UnlitMaterial()
        baseMaterial.color = .init(
            tint: pin.isDead ? .black : GameTablePlatformColor(pin.color)
        )
        baseModel.model?.materials = [baseMaterial]
        let isActiveAttacker = pin.id == activeAttackerPinId
        var highlightMaterial = UnlitMaterial()
        highlightMaterial.color = .init(
            tint: isActiveAttacker ? .systemBlue : .systemRed
        )
        highlightModel.model?.materials = [highlightMaterial]
        highlightModel.isEnabled = pin.isHighlighted || isActiveAttacker
        deathMarkModels.forEach { $0.isEnabled = pin.isDead }
        if hiddenForMaster {
            entity.components.set(OpacityComponent(opacity: 0.5))
        } else {
            entity.components.remove(OpacityComponent.self)
        }
        updateAccessibility(for: pin)
    }

    func setPhotoTexture(_ image: AKImage) {
        guard let cgImage = GameTableImage.cgImage(from: image),
              let texture = try? TextureResource(
                image: cgImage,
                options: .init(semantic: .color)
              ) else { return }
        var material = UnlitMaterial()
        material.color = .init(texture: .init(texture))
        photoPlane.model?.materials = [material]
    }

    /// Matches the 2D map's `pin.size.size × pinScale` sizing, projected from
    /// image points into table meters via `pointsToMeters` (see
    /// `MapTableProjection.metersPerPoint`) so a token covers the same
    /// fraction of the table that its pin covers of the map image.
    static func radius(for size: MapPinModel.MapPinSize, pointsToMeters: Float) -> Float {
        Float(size.size.width) * pointsToMeters / 2
    }

    private func applySize(_ size: MapPinModel.MapPinSize, pointsToMeters: Float) {
        let radius = Self.radius(for: size, pointsToMeters: pointsToMeters)
        let diameter = radius * 1.8
        baseModel.model?.mesh = .generateCylinder(height: 0.005, radius: radius)
        highlightModel.model?.mesh = .generateCylinder(
            height: 0.001,
            radius: radius * 1.18
        )
        photoPlane.model?.mesh = .generatePlane(
            width: diameter,
            depth: diameter,
            cornerRadius: diameter / 2
        )
        let deathBarLength = diameter * 0.72
        let deathBarThickness = max(diameter * 0.10, 0.0015)
        deathMarkModels.forEach {
            $0.model?.mesh = .generateBox(
                width: deathBarLength,
                height: 0.001,
                depth: deathBarThickness
            )
        }
        entity.components.set(
            CollisionComponent(
                shapes: [
                    .generateBox(
                        width: diameter,
                        height: 0.02,
                        depth: diameter
                    )
                ]
            )
        )
    }

    private func updateAccessibility(for pin: MapPinModel) {
        guard var accessibility = entity.components[AccessibilityComponent.self] else { return }
        accessibility.label = LocalizedStringResource("Map pin \(pin.name)", bundle: .module)
        accessibility.value = Self.accessibilityValue(for: pin)
        entity.components.set(accessibility)
    }

    private static func accessibilityValue(for pin: MapPinModel) -> LocalizedStringResource {
        switch (pin.isShown, pin.isDead, pin.isHighlighted) {
        case (true, false, false): LocalizedStringResource("Visible, Alive, Not Highlighted", bundle: .module)
        case (true, false, true): LocalizedStringResource("Visible, Alive, Highlighted", bundle: .module)
        case (true, true, false): LocalizedStringResource("Visible, Dead, Not Highlighted", bundle: .module)
        case (true, true, true): LocalizedStringResource("Visible, Dead, Highlighted", bundle: .module)
        case (false, false, false): LocalizedStringResource("Hidden, Alive, Not Highlighted", bundle: .module)
        case (false, false, true): LocalizedStringResource("Hidden, Alive, Highlighted", bundle: .module)
        case (false, true, false): LocalizedStringResource("Hidden, Dead, Not Highlighted", bundle: .module)
        case (false, true, true): LocalizedStringResource("Hidden, Dead, Highlighted", bundle: .module)
        }
    }
}

// MARK: - Room Hit Area

/// An invisible hit-test volume matching a room's fog outline, so the fog
/// covering it can be tapped directly on the table instead of only through
/// the room menu. The map's composite board texture still draws the visible
/// fog — this entity exists purely so `RoomComponent`-targeted gestures have
/// something to hit. Lives in `GameSetup.roomHitContainer`, parallel to how
/// `PinPawn` lives in `pinContainer`.
@MainActor
final class RoomHitArea {
    let roomId: UUID
    let entity: Entity
    private var currentCoordinates: [CGPoint]

    init(entry: MapEntryModel, projection: MapTableProjection) {
        roomId = entry.id
        currentCoordinates = entry.coordinates
        let hitEntity = Entity()
        hitEntity.name = "RoomHitArea-\(entry.name)"
        hitEntity.components.set(RoomComponent(roomId: entry.id))
        hitEntity.components.set(InputTargetComponent())
        hitEntity.components.set(HoverEffectComponent())
        hitEntity.components.set(Self.collision(for: entry.coordinates, projection: projection))
        var accessibility = AccessibilityComponent()
        accessibility.isAccessibilityElement = true
        accessibility.label = LocalizedStringResource("Room \(entry.name)", bundle: .module)
        accessibility.systemActions = .activate
        accessibility.customActions = [LocalizedStringResource("Toggle Room Focus", bundle: .module)]
        hitEntity.components.set(accessibility)
        entity = hitEntity
    }

    /// Rebuilds the hit volume when the room's outline changed.
    func update(entry: MapEntryModel, projection: MapTableProjection) {
        guard entry.coordinates != currentCoordinates else { return }
        currentCoordinates = entry.coordinates
        entity.components.set(Self.collision(for: entry.coordinates, projection: projection))
    }

    /// A thin convex volume enclosing the room polygon, projected onto the
    /// table plane. Concave outlines are approximated by their convex hull —
    /// fine for a fog-reveal hit target, unlike a physics collider.
    private static func collision(for coordinates: [CGPoint], projection: MapTableProjection) -> CollisionComponent {
        guard coordinates.count >= 3 else {
            return CollisionComponent(shapes: [])
        }
        let halfThickness: Float = 0.004
        let points = coordinates.flatMap { point -> [SIMD3<Float>] in
            let base = projection.tablePosition(for: point)
            return [
                SIMD3<Float>(base.x, base.y - halfThickness, base.z),
                SIMD3<Float>(base.x, base.y + halfThickness, base.z)
            ]
        }
        return CollisionComponent(shapes: [.generateConvex(from: points)])
    }
}

private enum GameTableImage {
    static func cgImage(from image: AKImage) -> CGImage? {
#if os(macOS)
        var proposedRect = CGRect(origin: .zero, size: image.size)
        return image.cgImage(
            forProposedRect: &proposedRect,
            context: nil,
            hints: nil
        )
#else
        return image.cgImage
#endif
    }
}
#endif
