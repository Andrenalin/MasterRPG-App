// @copyright André Trettin

import CoreRPG
import SwiftUI
import os.log

#if !os(tvOS)
import RealityKit
#if os(visionOS)
import GroupActivities
#endif

extension Logger {
    static let spaceViewer = Logger(subsystem: subsystem, category: "SpaceViewer")
}

struct SpaceViewer: View {
    let root: SpaceRootModel
    let id: UUID
    let isModal: Bool
    var isImmersiveSpace: Bool = false

    @Environment(ScenesManager.self) var scenesManager

    @Environment(\.dismiss) var dismiss
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    @State var rootEntity: Entity?
    @State var objectEntity: Entity?
    @State var nameEntity: Entity?
    @State var loadedItemId: UUID?

    /// Tracks the in-flight collision-shape-generation `Task` started by
    /// `loadEntity` so a rapid item switch cancels the stale generation
    /// instead of letting it keep running against an entity that may no
    /// longer be on screen. See CODE_AUDIT §3.8.
    @State var collisionShapeTask: Task<Void, Never>?

    @State var yaw: Float = .pi / 2
    @State var pitch: Float = 0
    @State var hasLoaded: Bool = false
    @State var loadError: String?

#if os(visionOS)
    /// Shows the small floating close button — only while the immersive space
    /// is displaying it, and only after a direct tap on the object.
    @State var showCloseButton = false

    /// True once this (window-embedded, non-immersive) instance has handed
    /// its entity off to the immersive space — see `SpaceHandoffModel`.
    @State var handedOffToImmersive = false

    /// The object's position when the current `ManipulationComponent` gesture
    /// began — compared against where it settled at `WillEnd` to detect
    /// "dragged far enough to count as pulled toward the immersive space."
    /// Window-embedded instances only; see `handleManipulationEnded`.
    @State var manipulationStartPosition: SIMD3<Float>?
    /// What the manipulation subscriptions call into. The subscription closures capture only this
    /// relay, never the view value: the view's `@State` storage holds the subscriptions, so a
    /// closure holding a copy of the view would be a retain cycle through the whole entity graph.
    /// The view installs the handlers on appear and clears them on disappear.
    /// See CODE_AUDIT_26 §3.2.
    @State var manipulationRelay = SpaceManipulationRelay()
    @State var manipulationBeganSubscription: EventSubscription?
    @State var manipulationEndedSubscription: EventSubscription?
    /// Holds the one-shot `SceneEvents.Update` wait `attachCloseButtonIfNeeded`
    /// uses to defer `rootEntity.addChild(closeButtonEntity)` — see that
    /// method's own doc for why a real engine tick is needed instead of a
    /// `Task { @MainActor }` hop.
    @State var closeButtonAttachSubscription: EventSubscription?
#endif

#if os(visionOS)
    // Shared immersive space (SharePlay): placement and manipulation sync.
    @Environment(\.immersiveSpaceDisplacement) var immersiveSpaceDisplacement
    @Environment(\.networkActions) var networkActions
    // `networkActions` alone doesn't distinguish a real SharePlay GroupSession
    // from a solo or local-network game — it's populated for all three. Only
    // this flag means "the system actually aligned a shared immersive space",
    // which is the one case the head-anchored placement below must give way to.
    @Environment(\.isSpaceSharePlayActive) var isSpaceSharePlayActive

    @State var lastSentTransform: SpaceTransformModel?
    @State var lastAcknowledgedTransform: SpaceTransformModel?
    @State var unacknowledgedTransformTicks = 0
    @State var isSharedPlacement = false
    /// True while a `ManipulationComponent` gesture is actively driving
    /// `objectEntity`'s transform — drives `sendTransformLoop`'s cadence
    /// (dense while manipulating, sparse otherwise) instead of streaming at
    /// one fixed rate regardless of whether anything is moving.
    @State var isManipulating = false
    /// Where the object floats above the game table — see `placeAboveTableIfNeeded`.
    @State var tablePlacement = SpaceTablePlacement()
#endif

    var body: some View {
        ZStack(alignment: .bottomLeading) {
#if os(visionOS)
            if handedOffToImmersive {
                SpaceViewerMovedToImmersiveSpaceView()
            } else if let loadError {
                SpaceViewerErrorView(message: loadError)
            } else {
                SpaceViewerProgressView(hasLoaded: hasLoaded)

                SpaceViewerContentView(
                    root: root,
                    id: id,
                    isImmersiveSpace: isImmersiveSpace,
                    loadedItemId: loadedItemId,
                    objectEntity: $objectEntity,
                    yaw: yaw,
                    pitch: pitch,
                    spaceAccessibilityLabel: spaceAccessibilityLabel,
                    rotate: { rotate(yawDelta: $0, pitchDelta: $1) },
                    moveObject: { moveObject(x: $0, y: $1, z: $2) },
                    nameEntity: $nameEntity,
                    showCloseButton: $showCloseButton,
                    loadEntity: { content in await loadEntity(into: content) },
                    attachCloseButtonIfNeeded: { attachments, content in attachCloseButtonIfNeeded(attachments, content: content) },
                    updateCloseButtonPosition: updateCloseButtonPosition
                )
            }
#else
            if let loadError {
                SpaceViewerErrorView(message: loadError)
            } else {
                SpaceViewerProgressView(hasLoaded: hasLoaded)

                SpaceViewerContentView(
                    root: root,
                    id: id,
                    isImmersiveSpace: isImmersiveSpace,
                    loadedItemId: loadedItemId,
                    objectEntity: $objectEntity,
                    yaw: yaw,
                    pitch: pitch,
                    spaceAccessibilityLabel: spaceAccessibilityLabel,
                    rotate: { rotate(yawDelta: $0, pitchDelta: $1) },
                    moveObject: { moveObject(x: $0, y: $1, z: $2) },
                    loadEntity: { content in await loadEntity(into: content) }
                )
            }
#endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
#if os(visionOS)
        // Immersive-space lifecycle tracking (`.immersiveSpaceTracker()`) is
        // applied at the `spaceImmersionWindow` call site instead of here —
        // see its comment. Doing it inside this view meant every item
        // replace (a `.id(id)` change tearing this whole view down and
        // rebuilding it) fired a spurious close/reopen of the tracked state.
        .applyIf(!isImmersiveSpace) {
            // A double-tap on the object moves it into the immersive space.
            // Deliberately not drag-based: any attempt to layer a second
            // `DragGesture().targetedToAnyEntity()` alongside `installGestures`'
            // own (even just chaining an extra `.onEnded` onto its existing
            // gesture) broke ordinary dragging and zooming outright. Until
            // that's understood well enough to risk touching again, this
            // stays the only trigger.
            $0.simultaneousGesture(
                SpatialTapGesture(count: 2)
                    .targetedToAnyEntity()
                    .onEnded { _ in
                        moveToImmersiveSpace()
                    }
            )
        }
        .onChange(of: scenesManager.getSceneState(for: .spaceViewer)) { _, newState in
            // The immersive space closed after the handoff: this window shows the object again
            // (it reloads its file). See CODE_AUDIT_26 §5.136.
            guard handedOffToImmersive, newState == .closed else { return }
            handedOffToImmersive = false
        }
        .onChange(of: immersiveSpaceDisplacement) {
            // A defensive re-check for SharePlay starting (or realigning) after
            // the model already loaded. `applySharedPlacementIfNeeded` no longer
            // keys its own gate off this value (see its doc comment) — this is
            // just "something about space alignment changed, make sure we've
            // switched off the head anchor if we're in a shared session."
            applySharedPlacementIfNeeded()
        }
        .onChange(of: isSpaceSharePlayActive) {
            // Re-check when SharePlay activates after the space already opened
            // solo — that's the only transition that should move the model off
            // the head anchor.
            applySharedPlacementIfNeeded()
        }
        .onChange(
            of: root.gameController.spaceGameModel.transform(
                for: id,
                version: root.gameController.gameItem(for: id).version
            ),
            initial: true
        ) { _, newValue in
            apply(remote: newValue)
        }
        .task(id: hasLoaded) {
            await sendTransformLoop()
        }
        .task(
            id: TablePlacementTrigger(
                hasLoaded: hasLoaded,
                isSharedPlacement: isSharedPlacement,
                tableId: root.tablePlacementReference?.id,
                displacement: immersiveSpaceDisplacement
            )
        ) {
            await placeAboveTableIfNeeded()
        }
        .onAppear {
            installManipulationHandlers()
        }
        .onDisappear {
            sendTransformIfChanged()
            manipulationRelay.clear()
        }
#endif
    }
}


#if os(visionOS)
// Note: SharePlay synchronization is handled at the GameRPG layer when opening
// the immersive space, not here. SpaceViewer is a generic module and should not
// depend on game-specific SharePlay logic.
#endif

#Preview("Space Viewer") {
    SpaceViewer(root: .preview, id: SpaceModel.previewId, isModal: false)
        .environment(ScenesManager())
}

#endif

#if os(visionOS)
/// The target of `SpaceViewer`'s `ManipulationComponent` event subscriptions. A reference type with
/// no view inside: the subscriptions (kept in the view's `@State`) capture it instead of the view
/// value, and the view clears its handlers when it disappears, so no cycle keeps the entity graph
/// alive. See CODE_AUDIT_26 §3.2.
@MainActor
final class SpaceManipulationRelay {
    var began: (@MainActor (Entity) -> Void)?
    var ended: (@MainActor (Entity) -> Void)?

    func clear() {
        began = nil
        ended = nil
    }
}
#endif