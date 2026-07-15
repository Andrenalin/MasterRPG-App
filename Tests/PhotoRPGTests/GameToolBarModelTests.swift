// @copyright André Trettin

import Foundation
import Testing

@testable import PhotoRPG

@Suite("Photo viewer toolbar")
@MainActor
struct GameToolBarModelTests {
    @Test("View reconstruction does not overwrite an in-progress rotation")
    func repeatedConfigurationPreservesViewerRotation() {
        // Given
        let photoId = UUID()
        let model = GameToolBarModel()
        model.configure(photoId: photoId, degrees: 90)
        model.rotateClockwise()

        // When
        model.configure(photoId: photoId, degrees: 90)

        // Then
        #expect(model.degrees == 180)
    }

    @Test("A different photo synchronizes its persisted rotation")
    func changingPhotoSynchronizesRotation() {
        // Given
        let model = GameToolBarModel()
        model.configure(photoId: UUID(), degrees: 270)
        model.rotateClockwise()

        // When
        model.configure(photoId: UUID(), degrees: 45)

        // Then
        #expect(model.degrees == 45)
    }

    @Test("Clockwise rotation remains normalized", arguments: [0.0, 360.0, -360.0, 720.0])
    func rotationIsNormalized(initialDegrees: Double) {
        // Given
        let model = GameToolBarModel()
        model.degrees = initialDegrees

        // When
        model.rotateClockwise()

        // Then
        #expect(model.degrees == 90)
    }
}
