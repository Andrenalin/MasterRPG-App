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
            let result = await session.run(configuration)

            switch result {
            case .granted:
                print("Spatial tracking session granted and running")
            case .denied:
                print("Spatial tracking denied by user - AR features unavailable")
            case .notDetermined:
                print("Spatial tracking authorization not determined")
            case .restricted:
                print("Spatial tracking restricted - may be due to device limitations or parental controls")
            @unknown default:
                print("Unknown spatial tracking authorization status")
            }
        }
    }
}

#endif
