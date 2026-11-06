// @copyright André Trettin

#if canImport(Testing)
import Testing
import simd

@testable import PhotoRPG

/// CODE_AUDIT_24 §7.1: the spatial photo's foreground is only placed when something moved it.
struct ForegroundPlacementGateTests {
    private func inputs(
        center: SIMD3<Float> = [0, 0, 0],
        extents: SIMD3<Float> = [1, 1, 0],
        scale: SIMD3<Float> = [1, 1, 1],
        isChanging: Bool = false
    ) -> ForegroundPlacementGate.Inputs {
        .init(
            windowCenter: center,
            windowExtents: extents,
            photoScale: scale,
            photoScreenSize: [1, 1],
            isPhotoChanging: isChanging
        )
    }

    @Test("The first frame places the foreground, frames with the same inputs do not")
    func settledPhotoIsPlacedOnce() {
        var gate = ForegroundPlacementGate()
        let placed = gate.needsPlacement(for: inputs())
        #expect(placed)
        for _ in 0..<100 {
            let placed = gate.needsPlacement(for: inputs())
            #expect(!placed)
        }
    }

    @Test("A moved or resized window, or a rescaled photo, places it again")
    func changedInputsPlaceAgain() {
        var gate = ForegroundPlacementGate()
        _ = gate.needsPlacement(for: inputs())

        var placed = gate.needsPlacement(for: inputs(center: [0.1, 0, 0]))
        #expect(placed)
        placed = gate.needsPlacement(for: inputs(center: [0.1, 0, 0]))
        #expect(!placed)
        placed = gate.needsPlacement(for: inputs(center: [0.1, 0, 0], extents: [2, 2, 0]))
        #expect(placed)
        placed = gate.needsPlacement(for: inputs(center: [0.1, 0, 0], extents: [2, 2, 0], scale: [2, 2, 1]))
        #expect(placed)
        placed = gate.needsPlacement(for: inputs(center: [0.1, 0, 0], extents: [2, 2, 0], scale: [2, 2, 1]))
        #expect(!placed)
    }

    @Test("While the photo converts its depth grows, so every frame places; the frame it settles places once more")
    func convertingPhotoPlacesEveryFrame() {
        var gate = ForegroundPlacementGate()
        for _ in 0..<5 {
            let placed = gate.needsPlacement(for: inputs(isChanging: true))
            #expect(placed)
        }
        var placed = gate.needsPlacement(for: inputs(isChanging: false))
        #expect(placed, "the final depth is placed")
        placed = gate.needsPlacement(for: inputs(isChanging: false))
        #expect(!placed)
    }

    @Test("Reset places the next frame")
    func resetPlacesAgain() {
        var gate = ForegroundPlacementGate()
        _ = gate.needsPlacement(for: inputs())
        gate.reset()
        let placed = gate.needsPlacement(for: inputs())
        #expect(placed)
    }
}
#endif
