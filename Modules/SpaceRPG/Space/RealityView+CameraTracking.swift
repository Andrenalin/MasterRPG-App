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

        do {
            if let result = await session.run(configuration) {
                print(result)
            } else {
                print("Unknown spatial tracking authorization status")
            }
        }
    }
}

#endif
