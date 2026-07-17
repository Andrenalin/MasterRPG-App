// @copyright André Trettin

#if os(iOS) || os(macOS)
import Foundation
import RealityKit
import RPGTabletopGameContent
import os.log

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
            let staticScene = try await Entity(
                named: "static_scene",
                in: tabletopGameContentBunlde
            )
            staticScene.name = "GameTableStaticScene"
            root.addChild(staticScene)
        } catch {
            // The dynamic map board and pins remain usable when the decorative
            // package scene cannot be loaded.
            Logger.gameTable.error("Failed to load portable table scene: \(error.localizedDescription, privacy: .public)")
        }
    }

    func applyScale(_ scale: Float) {
        root.scale = SIMD3<Float>(repeating: scale)
    }

    func placeTable(bottomY: Float) {
        root.position.y = bottomY
    }
}
#endif
