// @copyright André Trettin

#if os(iOS) || os(macOS) || os(visionOS)
import RealityKit
import RPGTabletopGameContent

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Shared RealityKit table-asset construction, used identically by both the
/// visionOS TabletopKit-backed `GameRenderer` and the iOS/macOS camera-based
/// `GameRenderer` — pure entity-construction code with no platform
/// dependency. See CODE_AUDIT §9.3.
@MainActor
enum TableAssetFactory {
    static func makePlainWoodTable() async throws -> ModelEntity {
        // Reuse only the package's wood material. The referenced table mesh is
        // deliberately discarded because it contains the decorative opening
        // and props that do not belong on the game board.
        let materialSource = try await Entity(
            named: "table_assembly",
            in: tabletopGameContentBundle
        )
        let table = ModelEntity(
            mesh: .generateBox(
                width: GameMetrics.tableEdge,
                height: GameMetrics.tableThickness,
                depth: GameMetrics.tableEdge
            )
        )
        if let sourceModel = firstModelComponent(in: materialSource) {
            table.model?.materials = sourceModel.materials
        } else {
            var fallbackMaterial = PhysicallyBasedMaterial()
            fallbackMaterial.baseColor = .init(
                tint: .init(red: 0.38, green: 0.2, blue: 0.08, alpha: 1)
            )
            fallbackMaterial.roughness = .init(floatLiteral: 0.75)
            table.model?.materials = [fallbackMaterial]
        }
        table.name = "PlainWoodTable"
        table.position.y = GameMetrics.tableThickness / 2
        return table
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
