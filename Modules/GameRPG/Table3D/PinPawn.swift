// @copyright André Trettin

#if os(iOS) || os(macOS) || os(visionOS)
import CoreRPG
import Foundation
import MapRPG
import RealityKit
import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

// The map pin pawn, split out of GameTableEntities.swift. See CODE_AUDIT_29 §9.9.

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
    /// Whether the pin's action menu is open. The menu stands over the figure, so the hit-test
    /// box then covers only the base: a look or pinch at a button must not land on the standee
    /// behind it. Closing the menu gives the whole figure back.
    var isMenuOpen = false {
        didSet {
            guard isMenuOpen != oldValue else { return }
            refreshCollision()
        }
    }
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
        let diameter = radius * GameMetrics.Pin.diameterPerRadius

        // Placeholder only — `update(pin:...)` always runs immediately after
        // construction (see `GameSetup.syncPins`) and sets the real,
        // health-derived color before this ever renders.
        var baseMaterial = UnlitMaterial()
        baseMaterial.color = .init(tint: .systemGray)
        baseModel = ModelEntity(mesh: .generateCylinder(height: GameMetrics.Pin.baseHeight, radius: radius), materials: [baseMaterial])
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
        photoPlane.position.y = GameMetrics.Pin.photoPlaneY

        var deathMaterial = UnlitMaterial()
        deathMaterial.color = .init(tint: .white)
        let deathBarLength = diameter * GameMetrics.Pin.deathBarLengthRatio
        let deathBarThickness = max(diameter * GameMetrics.Pin.deathBarThicknessRatio, GameMetrics.Pin.deathBarMinimumThickness)
        let firstDeathBar = ModelEntity(
            mesh: .generateBox(width: deathBarLength, height: GameMetrics.Pin.deathBarHeight, depth: deathBarThickness),
            materials: [deathMaterial]
        )
        firstDeathBar.name = "PinDeathMarkFirstBar"
        firstDeathBar.position.y = GameMetrics.Pin.deathBarY
        firstDeathBar.orientation = simd_quatf(angle: .pi / 4, axis: SIMD3<Float>(0, 1, 0))
        firstDeathBar.isEnabled = false

        let secondDeathBar = ModelEntity(
            mesh: .generateBox(width: deathBarLength, height: GameMetrics.Pin.deathBarHeight, depth: deathBarThickness),
            materials: [deathMaterial]
        )
        secondDeathBar.name = "PinDeathMarkSecondBar"
        secondDeathBar.position.y = GameMetrics.Pin.deathBarY
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
        pinEntity.components.set(CollisionComponent(shapes: [.generateBox(width: diameter, height: GameMetrics.Pin.collisionHeight, depth: diameter)]))
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
        Self.radius(for: currentSize, pointsToMeters: currentPointsToMeters) * GameMetrics.Pin.diameterPerRadius
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
    /// figure lies down or the pin's action menu is open).
    private func refreshCollision() {
        let diameter = diameter
        let shape: ShapeResource
        if let aspect = standeeAspect, !isStandeeFallen, !isMenuOpen {
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
        let diameter = radius * GameMetrics.Pin.diameterPerRadius
        baseModel.model?.mesh = .generateCylinder(height: GameMetrics.Pin.baseHeight, radius: radius)
        highlightModel.model?.mesh = .generateCylinder(height: Self.ringHeight, radius: radius * Self.ringRadiusMultiplier)
        photoPlane.model?.mesh = .generatePlane(width: diameter, depth: diameter, cornerRadius: diameter / 2)
        let deathBarLength = diameter * GameMetrics.Pin.deathBarLengthRatio
        let deathBarThickness = max(diameter * GameMetrics.Pin.deathBarThicknessRatio, GameMetrics.Pin.deathBarMinimumThickness)
        deathMarkModels.forEach {
            $0.model?.mesh = .generateBox(width: deathBarLength, height: GameMetrics.Pin.deathBarHeight, depth: deathBarThickness)
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

#endif
