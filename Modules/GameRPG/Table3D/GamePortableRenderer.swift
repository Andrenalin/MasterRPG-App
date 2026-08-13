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
    let camera: Entity
    weak var game: GameTableModel?
    private var didLoadAssets = false

    init() {
        root = Entity()
        root.name = "GameTableRoot"

        camera = Entity()
        camera.name = "GameTableCamera"
        camera.components.set(
            PerspectiveCameraComponent(
                near: 0.01,
                far: 10,
                fieldOfViewInDegrees: Self.verticalFieldOfViewDegrees
            )
        )
        updateCamera(for: CGSize(width: 1, height: 1))
    }

    func loadAssets() async {
        guard !didLoadAssets else { return }
        didLoadAssets = true

        do {
            root.addChild(try await TableAssetFactory.makePlainWoodTable())
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

    /// Frames the complete tabletop at a map-first viewing angle while
    /// adapting the distance for narrow iPhone and wide Mac viewports.
    func updateCamera(for viewportSize: CGSize) {
        guard viewportSize.width > 0, viewportSize.height > 0 else { return }

        let aspectRatio = Float(viewportSize.width / viewportSize.height)
        let verticalHalfFieldOfView = Self.verticalFieldOfViewDegrees * .pi / 360
        let horizontalHalfFieldOfView = atan(
            tan(verticalHalfFieldOfView) * aspectRatio
        )
        let elevation = (.pi / 2) - Self.angleFromTop
        let halfTableEdge = GameMetrics.tableEdge / 2
        let forwardDepth = halfTableEdge * cos(elevation)
        let framingMargin: Float = 1.12

        let distanceForWidth = forwardDepth
            + (halfTableEdge * framingMargin) / tan(horizontalHalfFieldOfView)
        let projectedTableDepth = halfTableEdge * sin(elevation)
        let distanceForHeight = forwardDepth
            + (projectedTableDepth * framingMargin) / tan(verticalHalfFieldOfView)
        let distance = max(distanceForWidth, distanceForHeight)

        let target = SIMD3<Float>(0, GameMetrics.tableThickness, 0)
        let cameraPosition = SIMD3<Float>(
            0,
            target.y + distance * sin(elevation),
            distance * cos(elevation)
        )
        camera.look(at: target, from: cameraPosition, relativeTo: nil)
    }
}

private extension GameRenderer {
    /// A 35° departure from top-down keeps the map readable while showing
    /// enough table depth for pins and dice to feel three-dimensional.
    static let angleFromTop: Float = 35 * .pi / 180
    static let verticalFieldOfViewDegrees: Float = 45
}
#endif
