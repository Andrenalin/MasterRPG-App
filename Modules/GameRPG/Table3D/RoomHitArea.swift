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

// The room hit-test volume, split out of GameTableEntities.swift. See CODE_AUDIT_29 §9.9.

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
    /// The name the entity names and accessibility label were made from.
    private var appliedName: String

    init(entry: MapEntryModel, projection: MapTableProjection) {
        roomId = entry.id
        appliedGeometry = (entry.coordinates, projection)
        appliedName = entry.name
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
        accessibility.label = Self.accessibilityLabel(for: entry)
        accessibility.systemActions = .activate
        accessibility.customActions = [LocalizedStringResource("Toggle Room Focus", bundle: .module)]
        hitEntity.components.set(accessibility)
        entity = hitEntity
    }

    /// An unnamed room or a hex cell gets a label too. See CODE_AUDIT_29 §8.4.
    private static func accessibilityLabel(for entry: MapEntryModel) -> LocalizedStringResource {
        let name = entry.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { return LocalizedStringResource("Room \(name)", bundle: .module) }
        return entry.isHexGrid
            ? LocalizedStringResource("Hex cell", bundle: .module)
            : LocalizedStringResource("Unnamed room", bundle: .module)
    }

    /// Rebuilds the convex hull only when the room's outline or the map projection changed;
    /// this runs on every pawn sync, and building a hull is comparatively expensive.
    func update(entry: MapEntryModel, projection: MapTableProjection) {
        // A renamed room gets its new label; skipped when unchanged, like the geometry.
        // See CODE_AUDIT_29 §8.4.
        if entry.name != appliedName {
            appliedName = entry.name
            entity.name = "RoomHitArea-\(entry.name)"
            outlineEntity.name = "RoomOutline-\(entry.name)"
            if var accessibility = entity.components[AccessibilityComponent.self] {
                accessibility.label = Self.accessibilityLabel(for: entry)
                entity.components.set(accessibility)
            }
        }
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
    /// The outline's own opacity: almost invisible until the hover effect draws it.
    private static let outlineOpacity: Float = 0.01

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
        material.blending = .transparent(opacity: .init(scale: Self.outlineOpacity))
        material.faceCulling = .none
        return ModelComponent(mesh: mesh, materials: [material])
    }

    /// A thin volume over the room polygon, projected onto the table plane: one convex shape
    /// for a convex room, one per triangle for a concave one, so a tap on an L- or U-shaped
    /// room's neighbour does not hit it (its convex hull reached over them and could reveal fog
    /// the game master meant to keep hidden). An outline that crosses itself falls back to the
    /// hull. See CODE_AUDIT_29 §5.25.
    private static func collision(for coordinates: [CGPoint], projection: MapTableProjection) -> CollisionComponent {
        guard coordinates.count >= 3 else {
            return CollisionComponent(shapes: [])
        }
        let halfThickness = GameMetrics.roomHitHalfThickness
        func prism(_ outline: [CGPoint]) -> ShapeResource {
            let points = outline.flatMap { point -> [SIMD3<Float>] in
                let base = projection.tablePosition(for: point)
                return [
                    SIMD3<Float>(base.x, base.y - halfThickness, base.z),
                    SIMD3<Float>(base.x, base.y + halfThickness, base.z)
                ]
            }
            return .generateConvex(from: points)
        }
        guard !PolygonTriangulation.isConvex(coordinates),
              let triangulation = PolygonTriangulation.triangles(of: coordinates) else {
            return CollisionComponent(shapes: [prism(coordinates)])
        }
        let shapes = triangulation.triangles.map { triangle in
            prism(triangle.map { triangulation.points[$0] })
        }
        return CollisionComponent(shapes: shapes)
    }
}

#endif
