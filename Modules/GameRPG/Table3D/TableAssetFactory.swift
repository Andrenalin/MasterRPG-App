// @copyright André Trettin

#if os(iOS) || os(macOS) || os(visionOS)
import Foundation
import RealityKit
import RPGTabletopGameContent

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Shared RealityKit table-asset construction, used identically by both the visionOS
/// TabletopKit-backed `GameRenderer` and the iOS/macOS camera-based `GameRenderer` — pure
/// entity-construction code with no platform dependency.
@MainActor
enum TableAssetFactory {
    /// The wood materials are borrowed from the package's decorative table, whose mesh is
    /// discarded (it contains an opening and props that don't belong on the game board). Loading
    /// that whole entity is costly, so it happens once per process.
    private static var cachedWoodMaterials: [any Material]?

    static func makePlainWoodTable() async throws -> ModelEntity {
        // `width`/`depth` are X/Z respectively (`generateBox`'s own convention) — the table's long
        // dimension runs along Z (`tableLength`), matching `Table.shape`'s
        // `.rectangular(width:height:thickness:)` for the same table.
        let table = ModelEntity(
            mesh: .generateBox(
                width: GameMetrics.tableWidth,
                height: GameMetrics.tableThickness,
                depth: GameMetrics.tableLength
            )
        )
        table.model?.materials = try await woodMaterials()
        table.name = "PlainWoodTable"
        table.position.y = GameMetrics.tableThickness / 2
        return table
    }

    private static func woodMaterials() async throws -> [any Material] {
        if let cachedWoodMaterials {
            return cachedWoodMaterials
        }
        let materialSource = try await Entity(
            named: "table_assembly",
            in: tabletopGameContentBundle
        )
        let materials: [any Material]
        if let sourceModel = firstModelComponent(in: materialSource) {
            materials = sourceModel.materials
        } else {
            var fallbackMaterial = PhysicallyBasedMaterial()
            fallbackMaterial.baseColor = .init(
                tint: .init(red: 0.38, green: 0.2, blue: 0.08, alpha: 1)
            )
            fallbackMaterial.roughness = .init(floatLiteral: 0.75)
            materials = [fallbackMaterial]
        }
        cachedWoodMaterials = materials
        return materials
    }

    static func firstModelComponent(in entity: Entity) -> ModelComponent? {
        if let model = entity.components[ModelComponent.self],
           !model.materials.isEmpty {
            return model
        }
        for child in entity.children {
            if let model = firstModelComponent(in: child) {
                return model
            }
        }
        return nil
    }
}
#endif
