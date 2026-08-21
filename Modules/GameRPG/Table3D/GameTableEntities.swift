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
/// and each platform's own board-texture rendering rather than duplicated —
/// see CODE_AUDIT §9.1.
enum GameTableImage {
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
    var loadedPhotoId: UUID?
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
        baseModel = ModelEntity(mesh: .generateCylinder(height: 0.005, radius: radius), materials: [baseMaterial])
        baseModel.name = "PinBase"

        // Placeholder only — `update(pin:...)` always runs immediately after
        // construction (see `GameSetup.syncPins`) and sets the real,
        // health/highlight/attacker-derived color before this ever renders.
        //
        // Sized/positioned to span the same visible band as `baseModel`'s own
        // upper half (see `Self.ringHeight`/`Self.ringPositionY`) — the table
        // surface sits only `GameMetrics.mapSurfaceClearance` (0.5mm) above
        // the solid table mesh, so a ring centered any lower than that, as
        // this one previously was, renders entirely *inside* the opaque
        // table and is never visible no matter its color.
        var highlightMaterial = UnlitMaterial()
        highlightMaterial.color = .init(tint: .systemGray)
        let highlight = ModelEntity(
            mesh: .generateCylinder(height: Self.ringHeight, radius: radius * 1.18),
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

        let pinEntity = Entity()
        pinEntity.name = "Pin-\(pin.name)"
        pinEntity.addChild(highlight)
        pinEntity.addChild(baseModel)
        pinEntity.addChild(photoPlane)
        pinEntity.addChild(firstDeathBar)
        pinEntity.addChild(secondDeathBar)
        pinEntity.components.set(PinComponent(pinId: pin.id))
        pinEntity.components.set(InputTargetComponent())
        pinEntity.components.set(CollisionComponent(shapes: [.generateBox(width: diameter, height: 0.02, depth: diameter)]))
        pinEntity.components.set(HoverEffectComponent())
        var accessibility = AccessibilityComponent()
        accessibility.isAccessibilityElement = true
        accessibility.label = LocalizedStringResource("Map pin \(pin.name)", bundle: .module)
        accessibility.value = Self.accessibilityValue(for: pin)
        accessibility.systemActions = .activate
        accessibility.customActions = [LocalizedStringResource("Toggle Pin Zoom", bundle: .module)]
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

    /// `baseModel` (height 0.005, centered on the pin's own Y) has its lower
    /// half embedded in the solid table mesh — only its upper half, local Y
    /// in roughly `-0.0005...0.0025`, actually clears the table surface and
    /// renders. The ring is sized/positioned to span that same visible band
    /// so it reads as a colored collar around the base's visible portion
    /// instead of being buried alongside its lower half.
    private static let ringHeight: Float = 0.003
    private static let ringPositionY: Float = 0.001

    /// Applies pin state without recreating the entity. The ring mirrors the
    /// 2D map's own pin border rules — health-colored (gray/green/orange/red,
    /// see `MapPinModel.healthBorderColor(for:)`) at rest, an active battle
    /// attacker overrides it blue, and a highlighted (but non-attacking) pin
    /// overrides it red — collapsed onto this single ring rather than the 2D
    /// map's two separate (inner health / outer highlight) rings, since a 3D
    /// token has no room for both without them visually competing.
    func update(
        pin: MapPinModel,
        position: SIMD3<Float>,
        hiddenForMaster: Bool,
        activeAttackerPinId: UUID? = nil,
        healthPercent: Double? = nil,
        pointsToMeters: Float
    ) {
        entity.position = position
        entity.scale = SIMD3<Float>(repeating: pin.isZoom ? 4.0 : 1.0)
        if pin.size != currentSize || pointsToMeters != currentPointsToMeters {
            currentSize = pin.size
            currentPointsToMeters = pointsToMeters
            applySize(pin.size, pointsToMeters: pointsToMeters)
        }
        var baseMaterial = UnlitMaterial()
        baseMaterial.color = .init(tint: pin.isDead ? .black : GameTablePlatformColor(pin.color))
        baseModel.model?.materials = [baseMaterial]

        let isActiveAttacker = pin.id == activeAttackerPinId
        let ringColor: Color = if isActiveAttacker {
            .blue
        } else if pin.isHighlighted {
            .red
        } else if pin.isDead {
            .black
        } else {
            MapPinModel.healthBorderColor(for: healthPercent)
        }
        var highlightMaterial = UnlitMaterial()
        highlightMaterial.color = .init(tint: GameTablePlatformColor(ringColor))
        highlightModel.model?.materials = [highlightMaterial]
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
    func setPhotoTexture(_ image: AKImage) {
        guard let cgImage = GameTableImage.cgImage(from: image),
              let texture = try? TextureResource(image: cgImage, options: .init(semantic: .color)) else { return }
        var material = UnlitMaterial()
        material.color = .init(texture: .init(texture))
        photoPlane.model?.materials = [material]
    }

    private func applySize(_ size: MapPinModel.MapPinSize, pointsToMeters: Float) {
        let radius = Self.radius(for: size, pointsToMeters: pointsToMeters)
        let diameter = radius * 1.8
        baseModel.model?.mesh = .generateCylinder(height: 0.005, radius: radius)
        highlightModel.model?.mesh = .generateCylinder(height: Self.ringHeight, radius: radius * 1.18)
        photoPlane.model?.mesh = .generatePlane(width: diameter, depth: diameter, cornerRadius: diameter / 2)
        let deathBarLength = diameter * 0.72
        let deathBarThickness = max(diameter * 0.10, 0.0015)
        deathMarkModels.forEach {
            $0.model?.mesh = .generateBox(width: deathBarLength, height: 0.001, depth: deathBarThickness)
        }
        entity.components.set(CollisionComponent(shapes: [.generateBox(width: diameter, height: 0.02, depth: diameter)]))
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

    init(entry: MapEntryModel, projection: MapTableProjection) {
        roomId = entry.id
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

    /// Always rebuilds: besides the room's own outline changing, the
    /// projection itself changes whenever a *different* room becomes focused
    /// (or focus clears) — same coordinates, different crop — so the
    /// `entry.coordinates` comparison alone can't gate this.
    func update(entry: MapEntryModel, projection: MapTableProjection) {
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
#endif
