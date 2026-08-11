// @copyright André Trettin

#if os(iOS)

import SwiftUI
import RealityKit
import os.log

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
                Logger.spaceViewer.debug("World tracking session result: \(String(describing: result), privacy: .public)")
            } else {
                Logger.spaceViewer.error("Unknown spatial tracking authorization status")
            }
        }
    }
}

#endif
