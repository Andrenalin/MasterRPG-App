// @copyright André Trettin

#if os(iOS) || os(macOS)
import Foundation
import RealityKit
import RPGTabletopGameContent
import os.log

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// RealityKit scene owner used by the camera-based table on iOS and macOS.
/// TabletopKit remains isolated in the visionOS `GameRenderer` implementation.
@MainActor
final class GameRenderer {
    let root: Entity
    weak var game: GameTableModel?
    private var didLoadAssets = false

    init() {
        root = Entity()
        root.name = "GameTableRoot"
    }

    func loadAssets() async {
        guard !didLoadAssets else { return }
        didLoadAssets = true

        do {
            root.addChild(try await Self.makePlainWoodTable())
        } catch {
            Logger.gameTable.error("Failed to load portable wood table: \(error.localizedDescription, privacy: .public)")
        }
    }

    func applyScale(_ scale: Float) {
        root.scale = SIMD3<Float>(repeating: scale)
    }

    func placeTable(bottomY: Float) {
        root.position.y = bottomY
    }
}

private extension GameRenderer {
    static func makePlainWoodTable() async throws -> ModelEntity {
        let materialSource = try await Entity(
            named: "table_assembly",
            in: tabletopGameContentBunlde
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
