// @copyright André Trettin

// REQUIRES: NSHandsTrackingUsageDescription key in the visionOS target's Info.plist.

#if os(visionOS)
import ARKit
import os.log
import CoreRPG

/// Detects a simultaneous middle-finger + thumb pinch on both hands and maps
/// the change in inter-hand distance to a uniform table scale factor.
@MainActor @Observable
final class TableScaleGestureController {

    // MARK: - Public state

    /// Live scale factor applied to the table (1.0 = original size).
    var tableScale: Float = 1.0

    /// Weak reference set by the view after the renderer is ready.
    weak var renderer: GameRenderer?

    // MARK: - Configuration

    let minScale: Float = 0.4
    /// Ceiling on how far the pinch gesture can grow the table. The volumetric
    /// window itself is a *fixed* size (`WindowVisionList`'s `.defaultSize(width: 2.15,
    /// depth: 2.15, in: .meters)`, chosen to exactly fit `GameMetrics.tableLength`/
    /// `tableWidth` at scale 1 plus a little clearance) — RealityKit clips anything
    /// outside those bounds rather than growing the window to fit, so scaling the
    /// table up doesn't "grow the volume," it just pushes the table's own edges (and
    /// its seats' dice) past the window's fixed bounds and off-screen. The window's
    /// system grab handle and this view's ornaments stay anchored to that fixed
    /// volume regardless, so an oversized table reads as the handle/ornaments having
    /// drifted away from it. `1.05` keeps the scaled table's footprint
    /// (`GameMetrics.tableLength` × `tableWidth`) inside the tighter of the window's
    /// two constraints — width (2.15 / 2.0 ≈ 1.075) and the depth actually available
    /// to the table after `GameRenderer.rootOffset`'s 0.5 m viewer clearance
    /// ((2.15 − 0.5) / 1.5 ≈ 1.10) — with a small margin for the table mesh's own rim.
    let maxScale: Float = 1.05

    /// Distance (m) between middle-finger tip and thumb tip that counts as a pinch.
    private let pinchThreshold: Float = 0.025

    // MARK: - Per-hand state (only mutated on @MainActor)

    private var leftPinchCenter: SIMD3<Float>?
    private var rightPinchCenter: SIMD3<Float>?

    // MARK: - Two-hand gesture state

    private var referenceDistance: Float?
    private var referenceScale: Float = 1.0

    // MARK: - Session

    /// Long-running hand-tracking loop. Start inside a `.task` modifier so
    /// SwiftUI cancels it automatically when the view disappears.
    func start() async {
        guard HandTrackingProvider.isSupported else {
            Logger.sharePlay.debug("Hand tracking not supported on this device")
            return
        }

        let session = ARKitSession()
        let handTracking = HandTrackingProvider()

        do {
            try await session.run([handTracking])
            // Each iteration suspends the @MainActor briefly between frames;
            // other main-actor work still runs between updates.
            for await update in handTracking.anchorUpdates {
                processHandAnchor(update.anchor)
            }
        } catch {
            Logger.sharePlay.error("Hand tracking session error: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Private processing

    private func processHandAnchor(_ anchor: HandAnchor) {
        guard anchor.isTracked, let skeleton = anchor.handSkeleton else {
            clearPinch(for: anchor.chirality)
            return
        }

        let middleJoint = skeleton.joint(.middleFingerTip)
        let thumbJoint  = skeleton.joint(.thumbTip)

        guard middleJoint.isTracked, thumbJoint.isTracked else {
            clearPinch(for: anchor.chirality)
            return
        }

        let origin    = anchor.originFromAnchorTransform
        let middlePos = (origin * middleJoint.anchorFromJointTransform).translation
        let thumbPos  = (origin * thumbJoint.anchorFromJointTransform).translation

        if simd_distance(middlePos, thumbPos) < pinchThreshold {
            let center = (middlePos + thumbPos) * 0.5
            setPinch(for: anchor.chirality, center: center)
        } else {
            clearPinch(for: anchor.chirality)
        }
    }

    private func setPinch(for chirality: HandAnchor.Chirality, center: SIMD3<Float>) {
        switch chirality {
        case .left:  leftPinchCenter  = center
        case .right: rightPinchCenter = center
        @unknown default: break
        }
        computeAndApplyScale()
    }

    private func clearPinch(for chirality: HandAnchor.Chirality) {
        switch chirality {
        case .left:  leftPinchCenter  = nil
        case .right: rightPinchCenter = nil
        @unknown default: break
        }
        // Reset the reference so the next two-hand activation starts fresh.
        if leftPinchCenter == nil || rightPinchCenter == nil {
            referenceDistance = nil
        }
    }

    private func computeAndApplyScale() {
        guard let left = leftPinchCenter, let right = rightPinchCenter else { return }

        let currentDistance = simd_distance(left, right)
        guard currentDistance > 0 else { return }

        if referenceDistance == nil {
            // Both hands just started pinching together — lock the reference.
            referenceDistance = currentDistance
            referenceScale    = tableScale
            return
        }

        guard let refDist = referenceDistance else { return }

        let rawScale  = referenceScale * (currentDistance / refDist)
        tableScale    = min(maxScale, max(minScale, rawScale))
        renderer?.applyScale(tableScale)
    }
}
#endif
