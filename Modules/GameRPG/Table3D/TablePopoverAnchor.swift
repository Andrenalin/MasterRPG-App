// @copyright André Trettin

#if os(iOS) || os(macOS) || os(visionOS)
import RealityKit

/// Stands a SwiftUI popover attachment on a point of the table: the pin action menu and the
/// dice results in the visionOS volume.
///
/// The attachment hangs under `entity`, raised by half of its own height, so `entity`'s origin
/// is the tip of the popover's arrow. The billboard turns `entity`, so the arrow keeps pointing
/// at its target from every viewing angle. `entity` belongs to the table root rather than to
/// the token it points at, so a token's size and zoom never scale the controls.
@MainActor
final class TablePopoverAnchor {
    let entity: Entity
    private(set) var attachment: Entity?
    private var attachmentHeight: Float = 0

    init(name: String) {
        entity = Entity()
        entity.name = name
        entity.components.set(BillboardComponent())
    }

    /// Adopts the attachment of the current `RealityView` mount.
    ///
    /// Discards any previously registered attachment first: `root` outlives one `RealityView`
    /// mount (see `GameTableView.initializeGameIfNeeded()`'s "if let game" branch), but an
    /// `Attachment` view does not — closing the volumetric window tears its `_HostingEntity`
    /// down. Without detaching the stale one before adopting the new one, both end up under
    /// `root` at once, and the next `content.add(root)` on reopen walks straight back over the
    /// old, mid-teardown entity — RealityKit aborts with
    /// `__CALLER_IS_PARENTING_AN_ENTITY_TO_AN_ENTITY_BEING_REMOVED__`. See `detach()`, called
    /// from `GameTableView`'s `.onDisappear`, which is the other half of the same fix — that
    /// one covers the disappear side, this one is a belt-and-suspenders guard for any path
    /// that re-registers without having gone through it.
    func register(_ attachment: Entity, in root: Entity) {
        if let previous = self.attachment, previous !== attachment {
            previous.removeFromParent()
        }
        self.attachment = attachment
        if entity.parent == nil {
            root.addChild(entity)
        }
        if attachment.parent !== entity {
            entity.addChild(attachment)
        }
        attachment.position = SIMD3<Float>(0, attachmentHeight / 2, 0)
    }

    /// Detaches the attachment from the persisted table root before its owning
    /// `RealityView`/window tears down — see `register(_:in:)`'s doc for why leaving it
    /// parented past that point crashes the *next* time the window opens, not this one.
    func detach() {
        attachment?.removeFromParent()
        attachment = nil
    }

    /// The attachment view reports its own height, in meters, whenever its layout changes.
    func attachmentHeightChanged(_ height: Float) {
        guard height.isFinite, height >= 0, attachmentHeight != height else { return }
        attachmentHeight = height
        attachment?.position = SIMD3<Float>(0, height / 2, 0)
    }

    /// Shows the popover with the tip of its arrow at `tip`, in the table root's space.
    func show(at tip: SIMD3<Float>) {
        entity.position = tip
        attachment?.isEnabled = true
    }

    func hide() {
        attachment?.isEnabled = false
    }
}
#endif
