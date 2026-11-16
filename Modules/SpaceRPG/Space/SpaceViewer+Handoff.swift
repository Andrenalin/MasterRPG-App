// @copyright André Trettin

import CoreRPG
import GroupActivities
import os.log
import RealityKit
import SwiftUI

#if os(visionOS)

// MARK: - Window → immersive space handoff

extension SpaceViewer {
    /// Minimum drag distance (meters) for `handleManipulationEnded` to treat a gesture as
    /// "grabbed and pulled toward the immersive space" rather than an idle orienting nudge.
    private static let handoffDragThreshold: Float = 0.15

    /// Fires on `ManipulationEvents.WillEnd` — the object has settled at its
    /// final position for this gesture. Compares that against where it stood
    /// when the gesture began (`ManipulationEvents.WillBegin`) and, if it
    /// moved far enough, hands it off to the immersive space. Purely
    /// observational — it doesn't touch the gesture itself, so it can't
    /// reintroduce the drag/zoom conflict a competing gesture caused before.
    @MainActor
    func installManipulationHandlers() {
        if isImmersiveSpace {
            manipulationRelay.began = { _ in
                self.isManipulating = true
                self.tablePlacement.markMoved()
            }
            manipulationRelay.ended = { _ in
                self.isManipulating = false
                self.sendTransformIfChanged()
            }
        } else {
            manipulationRelay.began = { entity in
                self.manipulationStartPosition = entity.position
            }
            manipulationRelay.ended = { entity in
                self.handleManipulationEnded(entity)
            }
        }
    }

    @MainActor
    func handleManipulationEnded(_ entity: Entity) {
        defer { manipulationStartPosition = nil }
        guard !isImmersiveSpace, let start = manipulationStartPosition else { return }
        // The object is normalized to ~0.5 m in the window (see `loadEntity`);
        // moving it about a third of its own size reads as "grabbed and
        // pulled," not an idle nudge while orienting it.
        guard simd_distance(entity.position, start) > Self.handoffDragThreshold else { return }
        moveToImmersiveSpace()
    }

    /// "Grabs" the object out of this (window-embedded) instance and moves it
    /// into the immersive space: hands the live entity off via
    /// `SpaceHandoffModel` — so the immersive instance re-parents it instead
    /// of reloading the file — then opens the immersive space. One-way only;
    /// see `SpaceHandoffModel`'s doc comment.
    @MainActor
    func moveToImmersiveSpace() {
        guard !isImmersiveSpace, let objectEntity else { return }
        root.handoffModel.handOff(itemId: id, entity: objectEntity)
        self.objectEntity = nil
        self.rootEntity = nil
        self.loadedItemId = nil
        self.hasLoaded = false
        handedOffToImmersive = true
        Task {
            // `openSpaceViewer` already replaces the displayed item in place when the space is
            // open on a *different* item (see its own doc comment / `ScenesManager`), so this
            // handoff — whose entity is already detached and `pending` in `SpaceHandoffModel` —
            // reliably gets adopted without a dismiss/reopen round trip. Forcing a
            // dismiss-then-reopen here (as this used to) meant a visible flicker/full teardown
            // for what should be a smooth in-place swap, and could lose unbroadcast local pose
            // changes to the previously-displayed entity since it was torn down immediately.
            // See CODE_AUDIT §5.19.
            await scenesManager.openSpaceViewer(selection: ItemSelection(itemId: id, entryId: nil))
            // The open can fail; the window must not stay on "Moved to Immersive Space" with its
            // object gone. See CODE_AUDIT_26 §5.136.
            if scenesManager.getSceneState(for: .spaceViewer) == .closed {
                handedOffToImmersive = false
            }
        }
    }

    /// Adopts an entity handed off by a window instance instead of loading
    /// the file again — see `SpaceHandoffModel`.
    @MainActor
    func adopt(_ handoff: SpaceHandoffModel.Pending, into content: some RealityViewContentProtocol) {
        let entity = handoff.entity
        self.objectEntity = entity

        // The entity already went through `loadEntity`'s centering once; this
        // re-centers relative to its now-parentless bounds, which is close
        // enough to a no-op that it's safe to apply again rather than special-
        // cased away.
        placeUnderHeadAnchor(entity, into: content)

        self.loadedItemId = id
        apply(
            remote: root.gameController.spaceGameModel.transform(
                for: id,
                version: root.gameController.gameItem(for: id).version
            )
        )
        adoptRetainedPoseForTablePlacement()
        hasLoaded = true
    }

    /// Anchors `entity` to the wearer's head — world-locking it at the
    /// current head position via `trackingMode = .once` so it doesn't end
    /// up far away and invisible if the person has moved since the ARKit
    /// session started (Apple's HeadTracking sample pattern) — 1.5m in
    /// front, roughly where a window sits by default, offset by `entity`'s
    /// own visual center so its pivot (often at the base/feet for USDZ
    /// files) doesn't throw off the placement. Adds the resulting anchor to
    /// `content`, sets `rootEntity`, and applies any pending SharePlay-
    /// shared placement. Shared by `loadEntity` and `adopt(_:into:)` — see
    /// CODE_AUDIT §9.2.
    @MainActor
    func placeUnderHeadAnchor(_ entity: Entity, into content: some RealityViewContentProtocol) {
        let visualCenter = entity.visualBounds(relativeTo: nil).center
        let headAnchor = AnchorEntity(.head)
        headAnchor.anchoring.trackingMode = .once
        // Combine centering offset with 1.5 m in front of the head anchor —
        // roughly where a window sits by default, straight ahead.
        entity.position = SIMD3(-visualCenter.x, -visualCenter.y, -visualCenter.z - 1.5)
        headAnchor.addChild(entity)
        content.add(headAnchor)
        self.rootEntity = headAnchor
        // If the system already aligned the space for SharePlay (joining an
        // active group immersion), move straight to the shared origin.
        applySharedPlacementIfNeeded()
    }
}

#endif
