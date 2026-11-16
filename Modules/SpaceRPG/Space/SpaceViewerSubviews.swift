// @copyright André Trettin

import CoreRPG
import os.log
import RealityKit
import SwiftUI

#if !os(tvOS)

// MARK: - Extracted subviews (CODE_AUDIT §8.3)
//
// Each gives SwiftUI its own diffing boundary, instead of the previous computed
// `some View` properties on `SpaceViewer` itself that all re-evaluated whenever any part
// of `SpaceViewer`'s body did.

struct SpaceViewerErrorView: View {
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.red)
            Text("Failed to Load 3D Model", bundle: .module)
                .font(.headline)
            Text(verbatim: message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct SpaceViewerProgressView: View {
    let hasLoaded: Bool

    var body: some View {
        ProgressView()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .progressViewStyle(.circular)
            .opacity(hasLoaded ? 0 : 1)
            .allowsHitTesting(!hasLoaded)
            .accessibilityHidden(hasLoaded)
    }
}

#if os(visionOS)
/// Re-runs `SpaceViewer.placeAboveTableIfNeeded` whenever any input to the
/// table-relative placement changes.
struct TablePlacementTrigger: Equatable {
    let hasLoaded: Bool
    let isSharedPlacement: Bool
    let tableId: Entity.ID?
    let displacement: Pose3D
}

struct SpaceViewerMovedToImmersiveSpaceView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.up.right.and.arrow.down.left.rectangle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Moved to Immersive Space", bundle: .module)
                .font(.headline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}
#endif

/// Wraps the platform reality view in the shared accessibility scaffolding
/// (label/value/rotate/move actions). Split out from `SpaceViewer` itself:
/// the multiple-trailing-closure `RealityView` initializer (three trailing
/// closures on visionOS, once attachments were added) combined with the long
/// `.accessibilityElement`/`.accessibilityAction` chain in one expression was
/// too much for the type checker to solve as a single unit — it reported a
/// spurious "cannot infer contextual base" on `.accessibilityElement` instead
/// of pointing at the real expression. Isolating the `RealityView`
/// construction into its own small view lets each half type-check
/// independently.
struct SpaceViewerContentView: View {
    let root: SpaceRootModel
    let id: UUID
    let isImmersiveSpace: Bool
    let loadedItemId: UUID?
    @Binding var objectEntity: Entity?
    let yaw: Float
    let pitch: Float
    let spaceAccessibilityLabel: Text
    let rotate: (Float, Float) -> Void
    let moveObject: (Float, Float, Float) -> Void
#if os(visionOS)
    @Binding var nameEntity: Entity?
    @Binding var showCloseButton: Bool
    let loadEntity: (RealityViewContent) async -> Void
    let attachCloseButtonIfNeeded: (RealityViewAttachments, RealityViewContent) -> Void
    let updateCloseButtonPosition: () -> Void
#else
    let loadEntity: (RealityViewCameraContent) async -> Void
#endif

    var body: some View {
        Group {
#if os(visionOS)
            SpaceViewerPlatformRealityView(
                loadedItemId: loadedItemId,
                id: id,
                objectEntity: $objectEntity,
                root: root,
                isImmersiveSpace: isImmersiveSpace,
                nameEntity: $nameEntity,
                showCloseButton: $showCloseButton,
                loadEntity: loadEntity,
                attachCloseButtonIfNeeded: attachCloseButtonIfNeeded,
                updateCloseButtonPosition: updateCloseButtonPosition
            )
#else
            SpaceViewerPlatformRealityView(
                loadedItemId: loadedItemId,
                id: id,
                objectEntity: $objectEntity,
                loadEntity: loadEntity
            )
#endif
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spaceAccessibilityLabel)
        .accessibilityValue(
            Text(
                "Yaw \(Angle.radians(Double(yaw)).degrees, format: .number.precision(.fractionLength(0))) degrees, pitch \(Angle.radians(Double(pitch)).degrees, format: .number.precision(.fractionLength(0))) degrees",
                bundle: .module
            )
        )
        .accessibilityAction(named: Text("Rotate Left", bundle: .module)) {
            rotate(-Self.accessibilityRotationStep, 0)
        }
        .accessibilityAction(named: Text("Rotate Right", bundle: .module)) {
            rotate(Self.accessibilityRotationStep, 0)
        }
        .accessibilityAction(named: Text("Tilt Up", bundle: .module)) {
            rotate(0, Self.accessibilityTiltStep)
        }
        .accessibilityAction(named: Text("Tilt Down", bundle: .module)) {
            rotate(0, -Self.accessibilityTiltStep)
        }
        .accessibilityAction(named: Text("Move Left", bundle: .module)) {
            moveObject(-Self.accessibilityMoveStep, 0, 0)
        }
        .accessibilityAction(named: Text("Move Right", bundle: .module)) {
            moveObject(Self.accessibilityMoveStep, 0, 0)
        }
        .accessibilityAction(named: Text("Move Up", bundle: .module)) {
            moveObject(0, Self.accessibilityMoveStep, 0)
        }
        .accessibilityAction(named: Text("Move Down", bundle: .module)) {
            moveObject(0, -Self.accessibilityMoveStep, 0)
        }
        .accessibilityAction(named: Text("Move Forward", bundle: .module)) {
            moveObject(0, 0, Self.accessibilityMoveStep)
        }
        .accessibilityAction(named: Text("Move Backward", bundle: .module)) {
            moveObject(0, 0, -Self.accessibilityMoveStep)
        }
    }

    /// Yaw/pitch step (radians) for the rotate-left/right/tilt-up/down accessibility actions.
    private static let accessibilityRotationStep: Float = .pi / 6
    private static let accessibilityTiltStep: Float = .pi / 12
    /// Translation step (meters) for the move-left/right/up/down/forward/backward
    /// accessibility actions.
    private static let accessibilityMoveStep: Float = 0.1
}

/// The actual `RealityView` construction: with attachments and
/// `ManipulationComponent`-driven gestures on visionOS, orbit camera controls
/// elsewhere. See `SpaceViewerContentView`'s doc comment for why this is
/// split out on its own.
struct SpaceViewerPlatformRealityView: View {
    let loadedItemId: UUID?
    let id: UUID
    @Binding var objectEntity: Entity?
#if os(visionOS)
    let root: SpaceRootModel
    let isImmersiveSpace: Bool
    @Binding var nameEntity: Entity?
    @Binding var showCloseButton: Bool
    let loadEntity: (RealityViewContent) async -> Void
    let attachCloseButtonIfNeeded: (RealityViewAttachments, RealityViewContent) -> Void
    let updateCloseButtonPosition: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
#else
    let loadEntity: (RealityViewCameraContent) async -> Void
#endif

    @ViewBuilder
    var body: some View {
#if os(visionOS)
        RealityView { content, attachments in
            await loadEntity(content)
            if isImmersiveSpace {
                attachCloseButtonIfNeeded(attachments, content)
            }
        } update: { content, attachments in
            // Only update if entity is loaded and valid
            guard let objectEntity, loadedItemId == id else { return }

            // No manual rotation here: `ManipulationComponent` owns and drives
            // `objectEntity.transform` directly during a gesture (translate,
            // rotate, and scale together) — reapplying a yaw/pitch-derived
            // rotation every frame from here would fight it.

            // Belt-and-suspenders: `loadEntity` can finish (and set `rootEntity`)
            // after `make` already ran when loading is slow, so retry here too.
            // Only the real ImmersiveSpace instance gets a close button — every
            // other SpaceViewer on screen is a plain 2D-embedded preview (detail
            // view, inline row, etc.) with its own dismiss affordance.
            if isImmersiveSpace {
                attachCloseButtonIfNeeded(attachments, content)
                nameEntity?.isEnabled = showCloseButton
                updateCloseButtonPosition()
            }
        } attachments: {
            if isImmersiveSpace {
                Attachment(id: "NameBarView") {
                    SpaceViewerCloseButtonView(root: root, id: id)
                }
            }
        }
        // No `.gesture()`/`.simultaneousGesture()` for drag, rotate, or zoom
        // here: `ManipulationComponent` (set on the entity in `loadEntity`)
        // handles all three natively — it's a self-contained RealityKit
        // component, not something wired up from the SwiftUI view side. See
        // Apple's "ManipulationComponent" documentation.
        .applyIf(isImmersiveSpace) {
            // Tap directly on the object to reveal the close button; tap again
            // to hide it. `.targetedToAnyEntity()` only fires when the tap
            // actually hits an entity with InputTargetComponent — i.e. the
            // model itself — so taps elsewhere in the space don't toggle it.
            $0.simultaneousGesture(
                SpatialTapGesture()
                    .targetedToAnyEntity()
                    .onEnded { _ in
                        withAnimation(reduceMotion ? nil : .default) {
                            showCloseButton.toggle()
                        }
                    }
            )
        }
#else
        RealityView { content in
            await loadEntity(content)
            // content here is RealityViewCameraContent, which exposes cameraTarget.
            // loadEntity receives only RealityViewContentProtocol so it can't set this.
            if let entity = objectEntity {
                content.cameraTarget = entity
            }
        } update: { content in
            // Only update if entity is loaded and valid
            guard let objectEntity, loadedItemId == id else { return }
        }
        // installGestures is visionOS-only: its DragGesture/MagnifyGesture targeted to
        // entities steal from .orbit — orbit handles both rotation and zoom natively.
        .realityViewCameraControls(.orbit)
#endif
    }
}

#if os(visionOS)
/// The small floating close button attached above the object in the
/// immersive space. See `SpaceViewer.attachCloseButtonIfNeeded`.
struct SpaceViewerCloseButtonView: View {
    let root: SpaceRootModel
    let id: UUID

    @Environment(ScenesManager.self) private var scenesManager

    var body: some View {
        Button {
            Task {
                // Marks this item as explicitly dismissed so a GM reveal
                // resync of the same item doesn't reopen it — see
                // `ScenesManager.explicitlyDismissedSpaceItemId`.
                await scenesManager.userDismissedSpaceViewer(itemId: id)
            }
        } label: {
            Label {
                Text(
                    "Close \(root.itemController.nameSync(itemId: id))",
                    bundle: .module
                )
            } icon: {
                Image(systemName: "xmark")
            }
            .labelStyle(.iconOnly)
        }
        .frame(width: 44, height: 44)
        .glassBackgroundEffect()
        .accessibilityLabel(Text("Close \(root.itemController.nameSync(itemId: id))", bundle: .module))
    }
}
#endif

#endif
