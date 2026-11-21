// @copyright André Trettin

#if os(iOS) || os(macOS) || os(visionOS)
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

/// Converts a game-table image to `CGImage` across every platform's `AKImage`
/// type (`UIImage` on iOS/visionOS, `NSImage` on macOS). Shared by `PinPawn`
/// and `BoardTextureInput` rather than duplicated.
enum GameTableImage {
    /// Upper bound of the long side, in pixels, of a re-rendered bitmap.
    private static let maximumBitmapDimension: CGFloat = 4_096

    /// The last converted board photo. Fog toggles and room edits rebuild the board texture for
    /// the same photo; the orientation bake / bitmap conversion ran each time. Identity of the
    /// source image is the key (the model keeps the same instance while the photo is current).
    /// See CODE_AUDIT_26 §7.47.
    @MainActor private static var cachedBoardImage: (source: AKImage, converted: CGImage)?

    @MainActor
    static func cachedCGImage(from image: AKImage) -> CGImage? {
        if let cached = cachedBoardImage, cached.source === image { return cached.converted }
        guard let converted = cgImage(from: image) else { return nil }
        cachedBoardImage = (image, converted)
        return converted
    }

    @MainActor
    static func clearBoardImageCache() {
        cachedBoardImage = nil
    }

    static func cgImage(from image: AKImage) -> CGImage? {
#if os(macOS)
        // `NSImage.cgImage(forProposedRect:)` can hand back the rep's raw bitmap without its EXIF
        // orientation, while `size` is the oriented size. Drawing the `NSImage` itself lets AppKit
        // apply the orientation, exactly like it does on screen; the bitmap is capped to keep huge
        // photos affordable.
        let orientedSize = image.size
        guard orientedSize.width > 0, orientedSize.height > 0 else { return nil }
        let pixelLongSide = image.representations
            .map { CGFloat(max($0.pixelsWide, $0.pixelsHigh)) }
            .max() ?? max(orientedSize.width, orientedSize.height)
        let longSide = min(max(1, pixelLongSide), maximumBitmapDimension)
        let scale = longSide / max(orientedSize.width, orientedSize.height)
        let width = max(1, Int((orientedSize.width * scale).rounded()))
        let height = max(1, Int((orientedSize.height * scale).rounded()))
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        image.draw(
            in: NSRect(x: 0, y: 0, width: width, height: height),
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()
#else
        // `UIImage.cgImage` is the raw bitmap without the EXIF orientation, while `size` (which the
        // board and the map's stored size use) is the oriented size. A sideways-stored photo — common
        // for high-resolution camera images — would otherwise render rotated and letterboxed, so
        // bake the orientation in.
        guard image.imageOrientation != .up else { return image.cgImage }
        let format = UIGraphicsImageRendererFormat.preferred()
        // Capped like the macOS bitmap: an oriented camera photo of 100+ megapixels would
        // otherwise be baked at full size. See CODE_AUDIT_26 §7.46.
        let pixelLongSide = max(image.size.width, image.size.height) * image.scale
        format.scale = pixelLongSide > maximumBitmapDimension
            ? image.scale * maximumBitmapDimension / pixelLongSide
            : image.scale
        format.opaque = false
        return UIGraphicsImageRenderer(size: image.size, format: format)
            .image { _ in image.draw(in: CGRect(origin: .zero, size: image.size)) }
            .cgImage
#endif
    }
}

/// Identifies a pin token entity for gesture targeting.
struct PinComponent: Component {
    let pinId: UUID
}

/// Identifies a room's fog hit-test volume for gesture targeting.
struct RoomComponent: Component {
    let roomId: UUID
}

/// A map pin token on the 3D table (player or monster), synced with the pins
/// of the current map. Lives as a plain RealityKit entity parented to
/// `GameSetup.pinContainer` — visionOS's TabletopKit only snapshots
/// `TableSetup` at init time, so a dynamic `EntityEquipment` addition would
/// never appear there. Pins are deliberately NOT TabletopKit equipment on any
/// platform: `mapState` is their single source of truth, TabletopKit pose
/// sync would fight it on visionOS.
@MainActor
final class PinPawn {
    let pinId: UUID
    let entity: Entity
    private let baseModel: ModelEntity
    private let photoPlane: ModelEntity
    private let highlightModel: ModelEntity
    private let deathMarkModels: [ModelEntity]
    /// The upright photo cutout on the base, see `setStandee(_:)`. Its `BillboardComponent` turns
    /// the figure toward the camera of each device while the pin is alive.
    private let standeeRoot: Entity
    private let standeeFront: ModelEntity
    /// Width / height of the shown cutout; `nil` while the token has no standee.
    private var standeeAspect: Float?
    /// Whether a shown standee lies down because the pin is dead.
    private var isStandeeFallen = false
    var loadedPhotoId: UUID?
    private var currentSize: MapPinModel.MapPinSize
    private var currentPointsToMeters: Float
    /// Everything `update(pin:...)` renders besides position, so an unchanged pin skips the
    /// material/component writes that would otherwise run on every map sync.
    private struct AppliedVisual: Equatable {
        let isDead: Bool
        let isHighlighted: Bool
        let isActiveAttacker: Bool
        let hiddenForMaster: Bool
        let healthColor: Color
        let name: String
        let isShown: Bool
        let color: Color
        let hasStandee: Bool
    }
    private var appliedVisual: AppliedVisual?

    init(pin: MapPinModel, pointsToMeters: Float) {
        pinId = pin.id
        currentSize = pin.size
        currentPointsToMeters = pointsToMeters
        let radius = Self.radius(for: pin.size, pointsToMeters: pointsToMeters)
        let diameter = radius * 1.8

        // Placeholder only — `update(pin:...)` always runs immediately after
        // construction (see `GameSetup.syncPins`) and sets the real,
        // health-derived color before this ever renders.
        var baseMaterial = UnlitMaterial()
        baseMaterial.color = .init(tint: .systemGray)
        baseModel = ModelEntity(mesh: .generateCylinder(height: 0.005, radius: radius), materials: [baseMaterial])
        baseModel.name = "PinBase"

        // Placeholder only — `update(pin:...)` always runs immediately after
        // construction (see `GameSetup.syncPins`) and sets the real,
        // health/highlight/attacker-derived color before this ever renders.
        //
        // Narrower than `baseModel` (see `Self.ringRadiusMultiplier`) and
        // stacked in the gap above it (see `Self.ringHeight`/`ringPositionY`)
        // so the pin reads, outside-in, as: `baseModel`'s own health color as
        // the outer rim, this ring's health/highlight/attacker color as a
        // middle band (the two only diverge while highlighted/attacking —
        // see `update(pin:...)`), then `photoPlane` on top. The table
        // surface sits only `GameMetrics.mapSurfaceClearance` (0.5mm) above
        // the solid table mesh, so a ring centered any lower than this
        // renders entirely *inside* the opaque table and is never visible no
        // matter its color.
        var highlightMaterial = UnlitMaterial()
        highlightMaterial.color = .init(tint: .systemGray)
        let highlight = ModelEntity(
            mesh: .generateCylinder(height: Self.ringHeight, radius: radius * Self.ringRadiusMultiplier),
            materials: [highlightMaterial]
        )
        highlight.name = "PinHighlightRing"
        highlight.position.y = Self.ringPositionY
        highlightModel = highlight

        var photoMaterial = UnlitMaterial()
        photoMaterial.color = .init(tint: GameTablePlatformColor(pin.color))
        photoPlane = ModelEntity(mesh: .generatePlane(width: diameter, depth: diameter, cornerRadius: diameter / 2), materials: [photoMaterial])
        photoPlane.name = "PinPhotoPlane"
        photoPlane.position.y = 0.004

        var deathMaterial = UnlitMaterial()
        deathMaterial.color = .init(tint: .white)
        let deathBarLength = diameter * 0.72
        let deathBarThickness = max(diameter * 0.10, 0.0015)
        let firstDeathBar = ModelEntity(
            mesh: .generateBox(width: deathBarLength, height: 0.001, depth: deathBarThickness),
            materials: [deathMaterial]
        )
        firstDeathBar.name = "PinDeathMarkFirstBar"
        firstDeathBar.position.y = 0.006
        firstDeathBar.orientation = simd_quatf(angle: .pi / 4, axis: SIMD3<Float>(0, 1, 0))
        firstDeathBar.isEnabled = false

        let secondDeathBar = ModelEntity(
            mesh: .generateBox(width: deathBarLength, height: 0.001, depth: deathBarThickness),
            materials: [deathMaterial]
        )
        secondDeathBar.name = "PinDeathMarkSecondBar"
        secondDeathBar.position.y = 0.006
        secondDeathBar.orientation = simd_quatf(angle: -.pi / 4, axis: SIMD3<Float>(0, 1, 0))
        secondDeathBar.isEnabled = false
        deathMarkModels = [firstDeathBar, secondDeathBar]

        // Disabled until `setStandee(_:)`. The root's origin is the standee's bottom edge, the
        // plane (XY, facing +Z) is lifted by half its height in `applyStandeeLayout()`.
        //
        // The billboard keeps +Z pointed at the active camera, which is the camera of the device
        // that renders it: every player sees the figure face them, and nothing is synced. It turns
        // around the root's origin (the feet) and, like the popovers' `TablePopoverAnchor`, on every
        // axis, so a figure seen from above leans toward the viewer. Its result is not readable from
        // the transform, which is why the hit-test box lives on the pin entity, not here.
        let front = ModelEntity(mesh: .generatePlane(width: diameter, height: diameter), materials: [UnlitMaterial()])
        front.name = "PinStandeeFront"
        let standee = Entity()
        standee.name = "PinStandee"
        standee.addChild(front)
        standee.components.set(BillboardComponent())
        standee.isEnabled = false
        standeeRoot = standee
        standeeFront = front

        let pinEntity = Entity()
        pinEntity.name = "Pin-\(pin.name)"
        pinEntity.addChild(highlight)
        pinEntity.addChild(baseModel)
        pinEntity.addChild(photoPlane)
        pinEntity.addChild(standee)
        pinEntity.addChild(firstDeathBar)
        pinEntity.addChild(secondDeathBar)
        pinEntity.components.set(PinComponent(pinId: pin.id))
        pinEntity.components.set(InputTargetComponent())
        pinEntity.components.set(CollisionComponent(shapes: [.generateBox(width: diameter, height: 0.02, depth: diameter)]))
        // A uniform glow over the whole pawn while it is looked at or touched. The default
        // spotlight is a faint feathered spot that disappears on these unlit materials.
        pinEntity.components.set(HoverEffectComponent(.highlight(
            HoverEffectComponent.HighlightHoverEffectStyle(color: .white, strength: 1.5)
        )))
        var accessibility = AccessibilityComponent()
        accessibility.isAccessibilityElement = true
        accessibility.label = LocalizedStringResource("Map pin \(pin.name)", bundle: .module)
        accessibility.value = Self.accessibilityValue(for: pin)
        accessibility.systemActions = .activate
        accessibility.customActions = [LocalizedStringResource("Show Pin Photo", bundle: .module)]
        pinEntity.components.set(accessibility)
        entity = pinEntity
    }

    /// Matches the 2D map's `pin.size.size × pinScale` sizing, projected from
    /// image points into table meters via `pointsToMeters` (see
    /// `MapTableProjection.metersPerPoint`) so a token covers the same
    /// fraction of the table that its pin covers of the map image.
    static func radius(for size: MapPinModel.MapPinSize, pointsToMeters: Float) -> Float {
        Float(size.size.width) * pointsToMeters / 2
    }

    /// Narrower than `baseModel`'s own radius (1.0×) so the base's identity
    /// color remains visible as the pin's outer rim, with this ring forming
    /// a middle band between it and `photoPlane` (0.9×) — an even ~5%-wide
    /// step on each side.
    private static let ringRadiusMultiplier: Float = 0.95
    /// Stacked in the gap between `baseModel`'s top face (local Y +0.0025)
    /// and `photoPlane` (local Y +0.004), clear of both by a real margin on
    /// each side rather than touching either exactly: two opaque RealityKit
    /// meshes sharing an exact Y (or, before this ring was narrowed, an
    /// exact radius) boundary z-fight — flicker between each other every
    /// frame — which previously showed as the base's own `pin.color`
    /// (defaults red) shimmering through the ring's actual color. Also clear
    /// of the table surface itself (only `GameMetrics.mapSurfaceClearance`,
    /// 0.5mm, above the solid table mesh) — anything centered at or below
    /// that renders entirely *inside* the opaque table and is never visible
    /// no matter its color.
    private static let ringHeight: Float = 0.001
    private static let ringPositionY: Float = 0.0033

    /// Applies pin state without recreating the entity. `baseModel` (the
    /// outer rim) is health-colored (gray/green/orange/red, see
    /// `MapPinModel.healthBorderColor(for:)`) rather than the pin's own
    /// `pin.color` identity — a pin with no linked hit-points entry reads as
    /// neutral gray, same as the 2D map. The middle ring mirrors the 2D
    /// map's highlight rule on top of that: an active battle attacker
    /// overrides it blue, a highlighted (but non-attacking) pin overrides it
    /// red, otherwise it shows the same health color as the base — so the
    /// two rings only diverge while a pin is actually highlighted/attacking.
    /// Both go black when dead, matching the base's death-mark bars.
    func update(
        pin: MapPinModel,
        position: SIMD3<Float>,
        hiddenForMaster: Bool,
        activeAttackerPinId: UUID? = nil,
        healthPercent: Double? = nil,
        pointsToMeters: Float
    ) {
        entity.position = position
        if pin.size != currentSize || pointsToMeters != currentPointsToMeters {
            currentSize = pin.size
            currentPointsToMeters = pointsToMeters
            applySize(pin.size, pointsToMeters: pointsToMeters)
        }
        let healthColor = MapPinModel.healthBorderColor(for: healthPercent)
        let isActiveAttacker = pin.id == activeAttackerPinId
        let visual = AppliedVisual(
            isDead: pin.isDead,
            isHighlighted: pin.isHighlighted,
            isActiveAttacker: isActiveAttacker,
            hiddenForMaster: hiddenForMaster,
            healthColor: healthColor,
            name: pin.name,
            isShown: pin.isShown,
            color: pin.color,
            hasStandee: standeeAspect != nil
        )
        guard visual != appliedVisual else { return }
        appliedVisual = visual

        var baseMaterial = UnlitMaterial()
        baseMaterial.color = .init(tint: pin.isDead ? .black : GameTablePlatformColor(healthColor))
        baseModel.model?.materials = [baseMaterial]

        let ringColor: Color = if isActiveAttacker {
            .blue
        } else if pin.isHighlighted {
            .red
        } else if pin.isDead {
            .black
        } else {
            healthColor
        }
        var highlightMaterial = UnlitMaterial()
        highlightMaterial.color = .init(tint: GameTablePlatformColor(ringColor))
        highlightModel.model?.materials = [highlightMaterial]
        // Without a photo the face shows the pin's own colour, which can be edited after the
        // token was created. See CODE_AUDIT_26 §5.81.
        // A standee stands on that colour as its plinth.
        if loadedPhotoId == nil || standeeAspect != nil {
            var faceMaterial = UnlitMaterial()
            faceMaterial.color = .init(tint: GameTablePlatformColor(pin.color))
            photoPlane.model?.materials = [faceMaterial]
        }
        if isStandeeFallen != pin.isDead {
            isStandeeFallen = pin.isDead
            applyStandeePose()
            refreshCollision()
        }
        highlightModel.isEnabled = true
        deathMarkModels.forEach { $0.isEnabled = pin.isDead }
        if hiddenForMaster {
            entity.components.set(OpacityComponent(opacity: 0.5))
        } else {
            entity.components.remove(OpacityComponent.self)
        }
        updateAccessibility(for: pin)
    }

    /// Puts the pin's photo (thumbnail) onto the token face.
    /// - Returns: whether the texture was made; a failed one leaves the face as it was, so the
    ///   caller does not record the photo as loaded. See CODE_AUDIT_23 §5.24.
    @discardableResult
    func setPhotoTexture(_ image: AKImage) -> Bool {
        guard let cgImage = GameTableImage.cgImage(from: image),
              let texture = try? TextureResource(image: cgImage, options: .init(semantic: .color)) else { return false }
        var material = UnlitMaterial()
        material.color = .init(texture: .init(texture))
        photoPlane.model?.materials = [material]
        // A new photo: the standee of the previous one must not stay until its own cutout is made.
        clearStandee()
        return true
    }

    /// Stands the photo's subject (`cutout`, with a transparent background) upright on the base,
    /// like an acrylic miniature. The disc below turns into a plain plinth in the pin's color.
    /// - Returns: whether the texture was made; on failure the token stays as it was.
    @discardableResult
    func setStandee(_ cutout: CGImage) -> Bool {
        guard cutout.width > 0, cutout.height > 0,
              let texture = try? TextureResource(image: cutout, options: .init(semantic: .color)) else { return false }
        var material = UnlitMaterial()
        material.color = .init(texture: .init(texture))
        // Alpha-clipped rather than blended: stable ordering against the ring, the disc and other
        // pins, at the price of a hard edge.
        material.opacityThreshold = 0.5
        standeeFront.model?.materials = [material]
        standeeAspect = Float(cutout.width) / Float(cutout.height)
        applyStandeeLayout()
        applyStandeePose()
        standeeRoot.isEnabled = true
        refreshCollision()
        var plinth = UnlitMaterial()
        plinth.color = .init(tint: GameTablePlatformColor(appliedVisual?.color ?? .gray))
        photoPlane.model?.materials = [plinth]
        return true
    }

    /// Removes the standee. The disc keeps the face it has; callers set that themselves.
    func clearStandee() {
        guard standeeAspect != nil else { return }
        standeeAspect = nil
        standeeRoot.isEnabled = false
        refreshCollision()
    }

    /// Back to the pin's color after its photo was removed.
    func clearPhotoTexture(for pin: MapPinModel) {
        var material = UnlitMaterial()
        material.color = .init(tint: GameTablePlatformColor(pin.color))
        photoPlane.model?.materials = [material]
        clearStandee()
        loadedPhotoId = nil
    }

    private var diameter: Float {
        Self.radius(for: currentSize, pointsToMeters: currentPointsToMeters) * 1.8
    }

    /// Sizes the two faces to the cutout's aspect inside the token's limits.
    private func applyStandeeLayout() {
        guard let aspect = standeeAspect else { return }
        let layout = PinStandeeLayout(aspect: aspect, diameter: diameter)
        standeeFront.model?.mesh = .generatePlane(width: layout.width, height: layout.height)
        standeeFront.position = SIMD3(0, layout.height / 2, 0)
    }

    /// Upright on the base and turned toward the camera, or lying down on it, face up and no
    /// longer billboarded, while the pin is dead.
    private func applyStandeePose() {
        guard let aspect = standeeAspect else { return }
        var billboard = standeeRoot.components[BillboardComponent.self] ?? BillboardComponent()
        if isStandeeFallen {
            let layout = PinStandeeLayout(aspect: aspect, diameter: diameter)
            billboard.blendFactor = 0
            standeeRoot.orientation = simd_quatf(angle: -.pi / 2, axis: SIMD3<Float>(1, 0, 0))
            standeeRoot.position = SIMD3(0, PinStandeeLayout.fallenY, layout.fallenRootZ)
        } else {
            billboard.blendFactor = 1
            standeeRoot.orientation = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
            standeeRoot.position = SIMD3(0, PinStandeeLayout.bottomY, 0)
        }
        standeeRoot.components.set(billboard)
    }

    /// The hit-test box: covers the upright figure, or the flat token otherwise (also when the
    /// figure lies down).
    private func refreshCollision() {
        let diameter = diameter
        let shape: ShapeResource
        if let aspect = standeeAspect, !isStandeeFallen {
            let layout = PinStandeeLayout(aspect: aspect, diameter: diameter)
            let size = layout.collisionSize(diameter: diameter)
            shape = .generateBox(size: size).offsetBy(translation: SIMD3(0, layout.collisionCenterY(), 0))
        } else {
            shape = .generateBox(width: diameter, height: PinStandeeLayout.flatCollisionHeight, depth: diameter)
        }
        entity.components.set(CollisionComponent(shapes: [shape]))
    }

    private func applySize(_ size: MapPinModel.MapPinSize, pointsToMeters: Float) {
        let radius = Self.radius(for: size, pointsToMeters: pointsToMeters)
        let diameter = radius * 1.8
        baseModel.model?.mesh = .generateCylinder(height: 0.005, radius: radius)
        highlightModel.model?.mesh = .generateCylinder(height: Self.ringHeight, radius: radius * Self.ringRadiusMultiplier)
        photoPlane.model?.mesh = .generatePlane(width: diameter, depth: diameter, cornerRadius: diameter / 2)
        let deathBarLength = diameter * 0.72
        let deathBarThickness = max(diameter * 0.10, 0.0015)
        deathMarkModels.forEach {
            $0.model?.mesh = .generateBox(width: deathBarLength, height: 0.001, depth: deathBarThickness)
        }
        applyStandeeLayout()
        applyStandeePose()
        refreshCollision()
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
    /// The room's outline ribbon: practically invisible until the room is looked at, then the
    /// hover effect draws it red on top of the board texture's green room border.
    private let outlineEntity: ModelEntity
    /// The outline and projection the current collision shape was built from.
    private var appliedGeometry: (coordinates: [CGPoint], projection: MapTableProjection)

    init(entry: MapEntryModel, projection: MapTableProjection) {
        roomId = entry.id
        appliedGeometry = (entry.coordinates, projection)
        let hitEntity = Entity()
        hitEntity.name = "RoomHitArea-\(entry.name)"
        hitEntity.components.set(RoomComponent(roomId: entry.id))
        hitEntity.components.set(InputTargetComponent())
        // The hit volume has no model of its own, so the effect lands on the outline child (a hover
        // effect applies to the whole entity hierarchy). `.full` draws the red at full strength even
        // though the outline's own material is almost fully transparent.
        hitEntity.components.set(HoverEffectComponent(.highlight(
            HoverEffectComponent.HighlightHoverEffectStyle(
                color: GameTablePlatformColor.red,
                strength: Self.highlightStrength,
                opacityFunction: .full
            )
        )))
        hitEntity.components.set(Self.collision(for: entry.coordinates, projection: projection))
        outlineEntity = ModelEntity()
        outlineEntity.name = "RoomOutline-\(entry.name)"
        outlineEntity.model = Self.outlineModel(for: entry.coordinates, projection: projection)
        hitEntity.addChild(outlineEntity)
        var accessibility = AccessibilityComponent()
        accessibility.isAccessibilityElement = true
        accessibility.label = LocalizedStringResource("Room \(entry.name)", bundle: .module)
        accessibility.systemActions = .activate
        accessibility.customActions = [LocalizedStringResource("Toggle Room Focus", bundle: .module)]
        hitEntity.components.set(accessibility)
        entity = hitEntity
    }

    /// Rebuilds the convex hull only when the room's outline or the map projection changed;
    /// this runs on every pawn sync, and building a hull is comparatively expensive.
    func update(entry: MapEntryModel, projection: MapTableProjection) {
        guard entry.coordinates != appliedGeometry.coordinates || projection != appliedGeometry.projection else {
            return
        }
        appliedGeometry = (entry.coordinates, projection)
        entity.components.set(Self.collision(for: entry.coordinates, projection: projection))
        outlineEntity.model = Self.outlineModel(for: entry.coordinates, projection: projection)
    }

    /// Width of the outline ribbon: the board texture's room border (8 map points) in table meters,
    /// but never thinner than a line that can still be seen and looked at.
    private static let outlinePointWidth: Float = 8
    /// How far the red glow overpowers the green board border under it. At 2.0 the red added to
    /// the green read yellow; a high strength saturates it to red.
    private static let highlightStrength: Float = 8
    private static let outlineMinimumWidth: Float = 0.003

    /// The room polygon as a flat ribbon on the board, drawn with an almost transparent red
    /// material. Its alpha is not zero so the renderer does not drop the mesh; the `.full` hover
    /// effect ignores it. Nil model for an outline that cannot form a ribbon.
    private static func outlineModel(for coordinates: [CGPoint], projection: MapTableProjection) -> ModelComponent? {
        guard coordinates.count >= 3 else { return nil }
        let half = max(projection.metersPerPoint * outlinePointWidth, outlineMinimumWidth) / 2
        let points = coordinates.map { projection.tablePosition(for: $0) }
        var positions: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        for index in points.indices {
            let start = points[index]
            let end = points[(index + 1) % points.count]
            let delta = SIMD3<Float>(end.x - start.x, 0, end.z - start.z)
            let length = simd_length(delta)
            guard length > 1e-6 else { continue }
            let direction = delta / length
            let normal = SIMD3<Float>(-direction.z, 0, direction.x) * half
            // Extended by half a width at both ends, so the corners of the outline are covered.
            let from = start - direction * half
            let to = end + direction * half
            let base = UInt32(positions.count)
            positions.append(contentsOf: [from + normal, from - normal, to + normal, to - normal])
            indices.append(contentsOf: [base, base + 1, base + 2, base + 1, base + 3, base + 2])
        }
        guard !positions.isEmpty else { return nil }
        var descriptor = MeshDescriptor(name: "RoomOutline")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.primitives = .triangles(indices)
        guard let mesh = try? MeshResource.generate(from: [descriptor]) else { return nil }
        var material = UnlitMaterial(color: GameTablePlatformColor.red)
        material.blending = .transparent(opacity: .init(floatLiteral: 0.01))
        material.faceCulling = .none
        return ModelComponent(mesh: mesh, materials: [material])
    }

    /// A thin convex volume enclosing the room polygon, projected onto the
    /// table plane. Concave outlines are approximated by their convex hull —
    /// fine for a fog-reveal hit target, unlike a physics collider.
    private static func collision(for coordinates: [CGPoint], projection: MapTableProjection) -> CollisionComponent {
        guard coordinates.count >= 3 else {
            return CollisionComponent(shapes: [])
        }
        let halfThickness = GameMetrics.roomHitHalfThickness
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
#endif
