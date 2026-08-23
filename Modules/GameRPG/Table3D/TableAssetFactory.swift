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
        // `width`/`depth` are X/Z respectively (`generateBox`'s own
        // convention) — the table's long dimension runs along Z
        // (`tableLength`), not X, matching `Table.shape`'s own
        // `.rectangular(width:height:thickness:)` for the same table. See
        // `PlayerSeat.seatPoses`'s own doc for why.
        let table = ModelEntity(
            mesh: .generateBox(
                width: GameMetrics.tableWidth,
                height: GameMetrics.tableThickness,
                depth: GameMetrics.tableLength
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
