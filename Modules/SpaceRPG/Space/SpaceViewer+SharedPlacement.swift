// @copyright André Trettin

import CoreRPG
import GroupActivities
import os.log
import RealityKit
import SwiftUI

#if os(visionOS)

// MARK: - Shared immersive space synchronization

extension SpaceViewer {
    /// Re-anchors the model from the local head pose to the immersive space
    /// origin, which the system aligns across all SharePlay participants.
    ///
    /// Gated on `isSpaceSharePlayActive` (an actual SharePlay `GroupSession`),
    /// not on `networkActions != nil` — `networkActions` is populated for solo
    /// and local-network games too, so gating on it fired this re-anchor on
    /// every open and dropped the model at the (fixed, world-origin) anchor,
    /// i.e. right on top of the user, instead of leaving it head-anchored in
    /// front of them. It's also not gated on `immersiveSpaceDisplacement !=
    /// .identity`. Per Apple's docs, the system reports `.identity` for
    /// whichever participant's own default space position already *is* the
    /// shared meeting point — that's a legitimate steady-state value, not an
    /// "alignment hasn't happened yet" signal. Gating on it meant that
    /// participant's model never left the head-locked anchor: everyone else's
    /// world-anchor-relative position/rotation broadcasts would land on a
    /// still-head-anchored entity for them, which is exactly the "translation/
    /// rotation not mapped into the other person's coordinate system" symptom.
    @MainActor
    func applySharedPlacementIfNeeded() {
        guard isImmersiveSpace, isSpaceSharePlayActive, !isSharedPlacement else { return }
        guard let anchor = rootEntity as? AnchorEntity, let objectEntity else { return }
        isSharedPlacement = true

        anchor.anchoring = AnchoringComponent(.world(transform: matrix_identity_float4x4))
        // Center the model at the shared origin, one meter up — every
        // participant computes the same coordinates.
        let center = objectEntity.visualBounds(relativeTo: anchor).center
        objectEntity.position += SIMD3(-center.x, 1.0 - center.y, -center.z)
    }

    /// Both the table volume and the just re-anchored immersive content need a
    /// rendered frame before `transformMatrix(relativeTo: .immersiveSpace)`
    /// reports their settled poses — retried once per scene update (about a
    /// second at 90 Hz) instead of assumed. See CODE_AUDIT_19 §3.16.
    private static let tablePlacementAttempts = 90

    /// Floats the object `SpaceTablePlacement.heightAboveTable` above the volumetric game table.
    ///
    /// In a SharePlay surround template the system puts the shared immersive
    /// origin on the floor *under* the table volume, so the fixed "origin + 1 m"
    /// from `applySharedPlacementIfNeeded` lands inside or below the tabletop.
    /// The table's real pose comes from `transformMatrix(relativeTo:
    /// .immersiveSpace)` (Apple's volume → immersive space conversion). Every
    /// participant computes the same shared-space point, so the regular
    /// transform broadcast stays consistent.
    ///
    /// Runs when the table opens, when shared placement starts, and when the
    /// system realigns the space. A realignment only re-places while nobody has
    /// moved the object since the last table placement.
    @MainActor
    func placeAboveTableIfNeeded() async {
        guard isImmersiveSpace, hasLoaded, isSharedPlacement,
              let table = root.tablePlacementReference else { return }
        guard tablePlacement.shouldPlace(onTable: table.id) else { return }
        for _ in 0..<Self.tablePlacementAttempts {
            guard let rootEntity, await SceneUpdateWaiter.nextUpdate(of: rootEntity) else { return }
            if placeAboveTable(table) { return }
        }
        Logger.spaceViewer.error("Could not resolve the game table pose in the immersive space")
    }

    @MainActor
    func placeAboveTable(_ table: Entity) -> Bool {
        guard !isManipulating,
              let anchor = rootEntity,
              let objectEntity,
              let tableTop = table.transformMatrix(relativeTo: .immersiveSpace),
              let anchorPose = anchor.transformMatrix(relativeTo: .immersiveSpace) else { return false }
        objectEntity.position += SpaceTablePlacement.objectOffset(
            tableTop: tableTop,
            anchorPose: anchorPose,
            objectCenter: objectEntity.visualBounds(relativeTo: anchor).center
        )
        tablePlacement.didPlace(onTable: table.id)
        return true
    }

    /// Marks the current table placement as settled when the object already
    /// has a synced pose, so opening it doesn't override where someone left it.
    @MainActor
    func adoptRetainedPoseForTablePlacement() {
        let version = root.gameController.gameItem(for: id).version
        guard root.gameController.spaceGameModel.transform(for: id, version: version) != nil else { return }
        tablePlacement.adoptRetainedPose(onTable: root.tablePlacementReference?.id)
    }

    @MainActor
    func apply(remote transform: SpaceTransformModel?) {
        guard isImmersiveSpace, let transform, let objectEntity else { return }

        // While this device is the one actively driving the object —
        // `ManipulationComponent` owns and drives `objectEntity.transform`
        // directly every frame — that live gesture is the sole source of
        // truth for the visible pose. Any network-sourced value observed
        // here during that window is stale by definition, most commonly this
        // device's own optimistic self-echo: `PlayerController.send()` /
        // `MasterController.send()` write the just-sent pose into
        // `spaceGameModel` asynchronously, serialized through
        // `GameRootModel.scheduleNetworkAction`'s queue, so it can land after
        // `lastSentTransform` below has already moved on to a newer pose —
        // which breaks the "this is just my own echo" equality check right
        // after it and used to fight the live gesture with a 100ms tween
        // pulling backward toward the stale value every time it happened.
        // Skipping outright here is also exactly "apply immediately, no
        // master checking": the hand/gesture input already *is* the
        // immediate local truth, so there is nothing to reconcile against
        // until the gesture ends. Bookkeeping still updates so
        // `sendTransformIfChanged`'s retry counter doesn't misfire once it does.
        guard !isManipulating else {
            lastAcknowledgedTransform = transform
            unacknowledgedTransformTicks = 0
            return
        }

        if transform == lastSentTransform {
            // The echo of our own just-completed gesture's optimistic local
            // apply, or another participant's rebroadcast matching what we
            // already have. Stop periodic retries without moving the model.
            lastAcknowledgedTransform = transform
            unacknowledgedTransformTicks = 0
            return
        }

        // Ease into the new pose instead of snapping to it. The sender streams
        // roughly every `transformBroadcastActiveThrottle` while a gesture is
        // in progress (and `transformBroadcastThrottle` otherwise); a tween
        // slightly longer than the active cadence overlaps consecutive
        // updates so both that cadence and ordinary network jitter — GroupActivities
        // routes through the FaceTime relay, not LAN, so latency is
        // noticeably higher than local network — read as continuous motion
        // rather than a series of teleports. `withAnimation` doesn't apply
        // here: `Entity` isn't part of SwiftUI's animatable state, so the
        // RealityKit-native tween (`HasTransform.move(to:relativeTo:duration:timingFunction:)`)
        // is used instead.
        objectEntity.move(
            to: Transform(
                scale: transform.scale,
                rotation: transform.orientation,
                translation: transform.position
            ),
            relativeTo: objectEntity.parent,
            duration: Self.remoteTransformEaseDuration,
            timingFunction: .linear
        )
        tablePlacement.markMoved()
        lastAcknowledgedTransform = transform
        unacknowledgedTransformTicks = 0
    }

    /// Idle-cadence throttle for `sendTransformLoop`'s reconciliation retries
    /// when no gesture is active. See CODE_AUDIT §9.14.
    private static let transformBroadcastThrottle: Duration = .milliseconds(300)
    /// Active-gesture cadence: dense enough for `apply(remote:)`'s tween to
    /// read as continuous motion on the receiving end, without broadcasting
    /// on every rendered frame (`ManipulationComponent` drives the local
    /// transform every frame; only a throttled sample of that is sent).
    private static let transformBroadcastActiveThrottle: Duration = .milliseconds(50)
    /// How long `apply(remote:)` takes to ease into each received pose.
    /// Slightly longer than `transformBroadcastActiveThrottle` so consecutive
    /// tweens overlap instead of leaving a visible pause between them.
    private static let remoteTransformEaseDuration: TimeInterval = 0.1

    /// Broadcasts local manipulations (drag / magnify / rotate) on the game
    /// control channel. Streams at `transformBroadcastActiveThrottle` while
    /// `isManipulating` (set from the `ManipulationEvents.WillBegin`/`WillEnd`
    /// subscriptions in `loadEntity`) and falls back to the sparser
    /// `transformBroadcastThrottle` otherwise — this is a reconciliation/retry
    /// heartbeat between gestures, not a live-motion stream, so it doesn't
    /// need the dense cadence.
    @MainActor
    func sendTransformLoop() async {
        guard isImmersiveSpace, hasLoaded, networkActions != nil else { return }
        while !Task.isCancelled {
            let interval = isManipulating ? Self.transformBroadcastActiveThrottle : Self.transformBroadcastThrottle
            try? await Task.sleep(for: interval)
            sendTransformIfChanged()
        }
    }

    @MainActor
    func sendTransformIfChanged() {
        guard let objectEntity else { return }
        let current = SpaceTransformModel(
            position: objectEntity.position,
            scale: objectEntity.scale,
            orientation: objectEntity.transform.rotation
        )
        guard lastSentTransform != nil else {
            // Baseline after load — don't broadcast the initial pose.
            lastSentTransform = current
            lastAcknowledgedTransform = current
            return
        }
        // Skip when nothing changed or when the current pose is one we just
        // received from another participant.
        let version = root.gameController.gameItem(for: id).version
        let remote = root.gameController.spaceGameModel.transform(for: id, version: version)
        if current == remote {
            lastAcknowledgedTransform = current
            unacknowledgedTransformTicks = 0
            return
        }
        if current == lastSentTransform {
            guard current != lastAcknowledgedTransform else { return }
            unacknowledgedTransformTicks += 1
            guard unacknowledgedTransformTicks >= 10 else { return }
        }
        broadcast(transform: current, version: version)
    }

    @MainActor
    func broadcast(transform: SpaceTransformModel, version: Int) {
        guard networkActions != nil else { return }
        unacknowledgedTransformTicks = 0
        lastAcknowledgedTransform = nil
        lastSentTransform = transform
        guard let data = transform.encodeData() else { return }
        networkActions?.game(
            NetworkCodableDataType(id: id, type: .space, version: version, data: data),
            .spaceTransform,
            nil
        )
    }
}

#endif
