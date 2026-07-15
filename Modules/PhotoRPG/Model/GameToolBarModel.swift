// @copyright André Trettin

import SwiftUI

@MainActor @Observable
final class GameToolBarModel {
    var degrees: Double = 0

    private var configuredPhotoId: UUID?
    private var configuredPhotoDegrees: Double?

    /// Synchronizes persisted photo rotation when the displayed photo changes without
    /// overwriting an in-progress viewer-only rotation during ordinary view updates.
    func configure(photoId: UUID, degrees: Double) {
        let normalizedDegrees = ImageViewportGeometry.normalize(degrees)
        guard configuredPhotoId != photoId || configuredPhotoDegrees != normalizedDegrees else {
            return
        }

        configuredPhotoId = photoId
        configuredPhotoDegrees = normalizedDegrees
        self.degrees = normalizedDegrees
    }

    func rotateClockwise() {
        degrees = ImageViewportGeometry.normalize(degrees + 90)
    }

    func degrees(for photoId: UUID, fallback: Double) -> Double {
        guard configuredPhotoId == photoId else {
            return ImageViewportGeometry.normalize(fallback)
        }
        return degrees
    }
}
