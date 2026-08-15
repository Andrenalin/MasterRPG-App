// @copyright André Trettin

#if os(visionOS)
import Foundation
import RealityKit

/// Hands a loaded RealityKit entity off between the window-embedded
/// `SpaceViewer` (the 2D detail view's preview card) and the `ImmersiveSpace`
/// instance, so moving a 3D object into the immersive space reuses the entity
/// that's already loaded and posed instead of reloading the USDZ file from
/// disk and losing the person's current rotation.
///
/// Modeled on Apple's "Transforming entities between RealityKit coordinate
/// spaces" sample: the entity is a single live `Entity` reference, detached
/// from one scene's root and re-parented under another scene's root — not
/// copied or reloaded. A live drag can't cross a scene boundary (there's no
/// gesture-continuation API for that), so the handoff is a discrete trigger
/// (double-tap on the object) rather than a continuous drag, matching the
/// sample's own double-tap-to-move interaction.
///
/// One-directional: window → immersive space only. There's no return trip —
/// closing the immersive space simply drops the handed-off entity, and the
/// window's `SpaceViewer` reloads fresh from disk if revisited.
@MainActor @Observable
final class SpaceHandoffModel {
    struct Pending {
        let itemId: UUID
        let entity: Entity
        let yaw: Float
        let pitch: Float
    }

    private(set) var pending: Pending?

    /// Detaches `entity` from its current parent and marks it ready for the
    /// immersive space to adopt on its next load pass. `yaw`/`pitch` carry
    /// over the window instance's current rotation state — the entity's own
    /// `transform.rotation` isn't enough on its own, since the immersive
    /// `SpaceViewer` drives rotation from its own fresh `yaw`/`pitch` state
    /// every update tick and would otherwise snap it back to the default pose.
    func handOff(itemId: UUID, entity: Entity, yaw: Float, pitch: Float) {
        entity.removeFromParent()
        pending = Pending(itemId: itemId, entity: entity, yaw: yaw, pitch: pitch)
    }

    /// Returns and clears the pending handoff for `itemId`, if any.
    func takePending(for itemId: UUID) -> Pending? {
        guard let pending, pending.itemId == itemId else { return nil }
        self.pending = nil
        return pending
    }
}
#endif
