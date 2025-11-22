// @copyright André Trettin

#if os(iOS)

import SwiftUI
import RealityKit

extension RealityKit.RealityViewCameraContent {
    @MainActor
    func setupWorldTracking() async {
        let configuration = SpatialTrackingSession.Configuration(
            tracking: [.plane],
            sceneUnderstanding: [.shadow],
            camera: .back
        )

        let session = SpatialTrackingSession()
        _ = await session.run(configuration)
    }
}

#endif
