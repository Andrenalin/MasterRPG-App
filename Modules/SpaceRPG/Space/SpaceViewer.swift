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

    @Environment(ScenesManager.self) private var scenesManager

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var rootEntity: Entity?
    @State private var objectEntity: Entity?
    @State private var nameEntity: Entity?
    @State private var loadedItemId: UUID?

    /// Tracks the in-flight collision-shape-generation `Task` started by
    /// `loadEntity` so a rapid item switch cancels the stale generation
    /// instead of letting it keep running against an entity that may no
    /// longer be on screen. See CODE_AUDIT §3.8.
    @State private var collisionShapeTask: Task<Void, Never>?

    @State private var yaw: Float = .pi / 2
    @State private var pitch: Float = 0
    @State private var hasLoaded: Bool = false
    @State private var loadError: String?

#if os(visionOS)
    /// Shows the small floating close button — only while the immersive space
    /// is displaying it, and only after a direct tap on the object.
    @State private var showCloseButton = false

    /// True once this (window-embedded, non-immersive) instance has handed
    /// its entity off to the immersive space — see `SpaceHandoffModel`.
    @State private var handedOffToImmersive = false

    /// The object's position when the current `ManipulationComponent` gesture
    /// began — compared against where it settled at `WillEnd` to detect
    /// "dragged far enough to count as pulled toward the immersive space."
    /// Window-embedded instances only; see `handleManipulationEnded`.
    @State private var manipulationStartPosition: SIMD3<Float>?
    @State private var manipulationBeganSubscription: EventSubscription?
    @State private var manipulationEndedSubscription: EventSubscription?
    /// Holds the one-shot `SceneEvents.Update` wait `attachCloseButtonIfNeeded`
    /// uses to defer `rootEntity.addChild(closeButtonEntity)` — see that
    /// method's own doc for why a real engine tick is needed instead of a
    /// `Task { @MainActor }` hop.
    @State private var closeButtonAttachSubscription: EventSubscription?
#endif

#if os(visionOS)
    // Shared immersive space (SharePlay): placement and manipulation sync.
    @Environment(\.immersiveSpaceDisplacement) private var immersiveSpaceDisplacement
    @Environment(\.networkActions) private var networkActions
    // `networkActions` alone doesn't distinguish a real SharePlay GroupSession
    // from a solo or local-network game — it's populated for all three. Only
    // this flag means "the system actually aligned a shared immersive space",
    // which is the one case the head-anchored placement below must give way to.
    @Environment(\.isSpaceSharePlayActive) private var isSpaceSharePlayActive

    @State private var lastSentTransform: SpaceTransformModel?
    @State private var lastAcknowledgedTransform: SpaceTransformModel?
    @State private var unacknowledgedTransformTicks = 0
    @State private var isSharedPlacement = false
    /// True while a `ManipulationComponent` gesture is actively driving
    /// `objectEntity`'s transform — drives `sendTransformLoop`'s cadence
    /// (dense while manipulating, sparse otherwise) instead of streaming at
    /// one fixed rate regardless of whether anything is moving.
    @State private var isManipulating = false
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
        .onDisappear {
            sendTransformIfChanged()
        }
#endif
    }
}

#if os(visionOS)
// MARK: - Shared immersive space synchronization

private extension SpaceViewer {
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

// MARK: - Window → immersive space handoff

private extension SpaceViewer {
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

private extension SpaceViewer {
    /// Normalized model size (meters) inside the window-embedded viewer.
    static let windowTargetSize: Float = 0.5
    /// Normalized model size (meters) inside the visionOS immersive space — larger since
    /// there's no window frame constraining it.
    static let immersiveTargetSize: Float = 1.0
    /// Below this world-space extent, normalizing scale would divide by a near-zero value;
    /// treated as "no meaningful geometry to normalize" instead.
    static let minimumNormalizableExtent: Float = 0.0001

    @MainActor
    func loadEntity(into content: some RealityViewContentProtocol) async {
        // Prevent reloading same model
        guard loadedItemId != id else { return }

#if os(visionOS)
        if isImmersiveSpace, let handoff = root.handoffModel.takePending(for: id) {
            adopt(handoff, into: content)
            return
        }
#endif

        do {
            guard let url = await root.itemController.loadableUrl(itemId: id) else {
                loadError = String(
                    localized: "Could not access the 3D model file for item \(id.uuidString).",
                    bundle: .module
                )
                hasLoaded = true
                return
            }

            // Keep security-scoped resource access active during entire loading process
            let hasAccess = url.startAccessingSecurityScopedResource()

            defer {
                if hasAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            // Load entity from USDZ file
            let loadedEntity = try await Entity(contentsOf: url, withName: "3DMaster")

            // Validate the loaded entity has content
            guard loadedEntity.children.count > 0 || loadedEntity.components.count > 0 else {
                loadError = String(localized: "The 3D model is empty.", bundle: .module)
                hasLoaded = true
                return
            }

            // Use loadedEntity directly as root on all platforms.
            // The old 100 m container box caused the virtual camera to auto-zoom out to
            // frame the entire container, making the actual model appear tiny inside it.
            let newRootEntity = loadedEntity
            self.objectEntity = loadedEntity

            // Configure interaction on the root entity, not one arbitrarily-found
            // sub-mesh: a prior approach walked only the first-child chain
            // looking for a single ModelEntity, so a multi-part USDZ (siblings, not
            // nested under a single "first child" path) only got interactivity —
            // and only moved — on whichever one part it happened to find, and a
            // model whose mesh wasn't reachable that way at all (e.g. the root
            // entity is itself the ModelEntity, with no children to descend into)
            // got none. Putting these on the root and generating collision shapes
            // recursively covers the whole hierarchy as one hit-testable, draggable
            // unit regardless of how the file's internal structure is organized.
#if os(visionOS)
            // `ManipulationComponent` (visionOS 26+) is Apple's own built-in
            // drag/rotate/scale component: no SwiftUI `.gesture()` is
            // wired up anywhere for it (see `SpaceViewerPlatformRealityView`). It sets
            // its own InputTargetComponent/CollisionComponent/HoverEffectComponent,
            // generating the collision shape from the entity's bounding box as
            // a placeholder until the more accurate recursive shape below lands.
            ManipulationComponent.configureEntity(
                loadedEntity,
                hoverEffect: .shader(.default),
                allowedInputTypes: [.direct, .indirect]
            )
            // Default `releaseBehavior` is `.reset` — it animates the object
            // back to its pose *at the moment `configureEntity` ran* the
            // instant someone lets go, which is exactly the "snaps back"
            // symptom. `.stay` leaves it wherever the gesture ended, matching
            // Apple's own "Manipulate with solid collisions" sample.
            loadedEntity.components[ManipulationComponent.self]?.releaseBehavior = .stay

            // Watch `ManipulationComponent`'s own event stream (not a second
            // gesture — see the "drag is gone" history on `moveToImmersiveSpace`)
            // for two different purposes depending on which instance this is.
            if !isImmersiveSpace {
                // Window-embedded instance: detect "dragged far enough" and
                // hand the object off to the immersive space.
                manipulationBeganSubscription = content.subscribe(
                    to: ManipulationEvents.WillBegin.self
                ) { [weak loadedEntity] event in
                    guard event.entity == loadedEntity else { return }
                    Task { @MainActor in
                        self.manipulationStartPosition = event.entity.position
                    }
                }
                manipulationEndedSubscription = content.subscribe(
                    to: ManipulationEvents.WillEnd.self
                ) { [weak loadedEntity] event in
                    guard event.entity == loadedEntity else { return }
                    Task { @MainActor in
                        self.handleManipulationEnded(event.entity)
                    }
                }
            } else {
                // Immersive-space instance: no handoff detection needed (it's
                // already the immersive one), but this is the instance that
                // actually broadcasts — track gesture activity so
                // `sendTransformLoop` switches to the dense active cadence
                // only while someone is really dragging/rotating/scaling it,
                // and flush the settled pose the instant the gesture ends
                // instead of waiting for the next active-cadence tick.
                manipulationBeganSubscription = content.subscribe(
                    to: ManipulationEvents.WillBegin.self
                ) { [weak loadedEntity] event in
                    guard event.entity == loadedEntity else { return }
                    Task { @MainActor in
                        self.isManipulating = true
                    }
                }
                manipulationEndedSubscription = content.subscribe(
                    to: ManipulationEvents.WillEnd.self
                ) { [weak loadedEntity] event in
                    guard event.entity == loadedEntity else { return }
                    Task { @MainActor in
                        self.isManipulating = false
                        self.sendTransformIfChanged()
                    }
                }
            }
#else
            // No SwiftUI `.gesture()` is wired up for this platform either — see the `#else`
            // branch of `SpaceViewerPlatformRealityView`, which drives whole-scene orbit/zoom via
            // `.realityViewCameraControls(.orbit)` instead of per-entity drag. These two
            // components are still worth setting on their own: `HoverEffectComponent` alone
            // drives RealityKit's built-in trackpad/pointer hover highlight, independent of any
            // custom gesture pipeline. See CODE_AUDIT §9.1.
            loadedEntity.components.set(InputTargetComponent())
            loadedEntity.components.set(HoverEffectComponent(.shader(.default)))
#endif
            loadedEntity.components.set(GroundingShadowComponent(castsShadow: true))

            // Generate collision shapes asynchronously so this doesn't block the rest of
            // `loadEntity`. `Task.detached` was pointless here: `Entity`/`ModelEntity` are
            // MainActor-bound, so the detached task immediately hopped back via
            // `MainActor.run` anyway — this is already running on the Main Actor (`loadEntity`
            // is `@MainActor`), so a plain structured Task keeps the same "don't block, run
            // shortly after" behavior without the detach/re-attach indirection.
            collisionShapeTask?.cancel()
            collisionShapeTask = Task(name: "RealityKit Collision Shapes", priority: .utility) { @MainActor in
                guard !Task.isCancelled else { return }
                // RealityKit's `generateCollisionShapes` is synchronous with no interrupt
                // hook, so a cancellation requested once it starts has no effect until it
                // finishes. This short debounce gives a rapid follow-up entity switch (the
                // scenario this task exists to protect against) a real suspension point to
                // cancel through *before* the expensive call starts, instead of only being
                // checked once, immediately preceding a call nothing can then stop. See
                // CODE_AUDIT.md §3.9.
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled else { return }
                let trace = PerformanceTrace.begin(
                    "CollisionShapeGeneration",
                    source: "SpaceViewer",
                    count: 1
                )
                defer { trace?.end() }
                loadedEntity.generateCollisionShapes(recursive: true, static: true)
            }

            // Normalize scale using world-space base extents (Apple VolumetricWindow pattern).
            // visualBounds(relativeTo: nil) = world space, then divide by current scale to
            // get the "natural" extents at scale=1 — this correctly undoes any embedded
            // USDZ unit transforms that relativeTo:entity misses.
#if os(visionOS)
            let targetSize: Float = isImmersiveSpace ? Self.immersiveTargetSize : Self.windowTargetSize
#else
            let targetSize: Float = Self.windowTargetSize
#endif
            let baseExtents = loadedEntity.visualBounds(relativeTo: nil).extents / loadedEntity.scale
            let maxBase = max(baseExtents.x, max(baseExtents.y, baseExtents.z))
            if maxBase > Self.minimumNormalizableExtent && maxBase.isFinite {
                loadedEntity.scale = SIMD3<Float>(repeating: targetSize / maxBase)
            }

#if os(visionOS)
            if isImmersiveSpace {
                // Hard-coded world coords fail when the user has moved since the ARKit
                // session started — the entity ends up far away and invisible.
                // Apple pattern (HeadTracking sample): anchor to head with trackingMode=.once
                // which world-locks the entity at the current head position.
                placeUnderHeadAnchor(loadedEntity, into: content)
            } else {
                // Shift the entity so its visual centre sits at the world origin.
                // Most USDZ files have their pivot at the base/feet; without this the orbit
                // camera targets the feet and zooming in shows only the bottom of the model.
                loadedEntity.position = -loadedEntity.visualBounds(relativeTo: nil).center
                content.add(newRootEntity)
                self.rootEntity = newRootEntity
            }
#else
            // Shift the entity so its visual centre sits at the world origin.
            // Most USDZ files have their pivot at the base/feet; without this the orbit
            // camera targets the feet and zooming in shows only the bottom of the model.
            loadedEntity.position = -loadedEntity.visualBounds(relativeTo: nil).center
            content.add(newRootEntity)
            self.rootEntity = newRootEntity
#endif

            self.loadedItemId = id

            #if os(visionOS)
            // Messenger can deliver the latest pose before the Journal-backed
            // USDZ finishes loading. Apply the retained, item/version-scoped
            // state now that the entity and anchor exist.
            apply(
                remote: root.gameController.spaceGameModel.transform(
                    for: id,
                    version: root.gameController.gameItem(for: id).version
                )
            )
            #endif

        } catch let error as DecodingError {
            loadError = String(
                localized: "The 3D model format could not be read: \(error.localizedDescription)",
                bundle: .module
            )
            Logger.spaceViewer.error("Decoding error loading 3D entity: \(error.localizedDescription, privacy: .public)")
        } catch {
            loadError = String(
                localized: "The 3D model could not be loaded: \(error.localizedDescription)",
                bundle: .module
            )
            Logger.spaceViewer.error("Error loading 3D entity from URL: \(error.localizedDescription, privacy: .public)")
        }

        hasLoaded = true
    }

#if os(visionOS)
    /// Adds the close-button attachment as a child of `rootEntity` (the
    /// anchor, not `objectEntity`) the first time both exist. Parenting it —
    /// instead of computing a one-shot world position in a second, separate
    /// `RealityView` scene (the previous approach) — means the button is
    /// governed by the *same* RealityKit scene graph as the model and tracks
    /// automatically as the anchor is re-parented (`applySharedPlacementIfNeeded`)
    /// or the model is dragged, matching `GameTableModel.registerPinMenuAttachment`'s
    /// convention of parenting UI to a stable ancestor rather than the entity
    /// it labels, so drag/rotate/scale manipulation never distorts the button.
    ///
    /// The `rootEntity.addChild(closeButtonEntity)` call is deliberately
    /// deferred to the next `SceneEvents.Update` tick rather than made inline —
    /// mirrors `GameTableView.waitForFirstRenderedFrame(of:)`'s own reasoning:
    /// proof of an actual rendered frame is a stronger signal than any fixed
    /// number of `Task` turns. The first call here runs from `RealityView`'s
    /// `make` closure immediately after `loadEntity` → `placeUnderHeadAnchor`
    /// has just called `content.add(headAnchor)` for the *same* `rootEntity` —
    /// RealityKit's own engine-side insertion of that just-added anchor
    /// subtree (`re::ecs2::Scene::addToAllEntitiesRecursively`) can still be
    /// in flight at that instant. Parenting this attachment's own
    /// `_HostingEntity` to `rootEntity` in that same synchronous continuation
    /// crashed visionOS 26.5 — reproducibly, on first open, nothing else
    /// closing — inside RealityKit's engine with
    /// `__CALLER_IS_PARENTING_AN_ENTITY_TO_AN_ENTITY_BEING_REMOVED__`
    /// (`SwiftUI._HostingEntity.didActivate(in:)` → `re::ecs2::Entity::setParentInternal`).
    ///
    /// A one-`Task`-turn defer (the original fix) wasn't actually enough:
    /// reproduced again opening the immersive space while a second,
    /// window-embedded `SpaceViewer` for the same item was already on screen
    /// (`ItemDetailContentView`'s inline preview) — the crash's own stack
    /// showed the whole cascade (SwiftUI's `DisplayList.ViewUpdater`
    /// reinserting subviews, `CALayerSwizzle` translating that into ECS
    /// entity reparenting, six levels of recursive `addToAllEntitiesRecursively`
    /// down the just-loaded USDZ hierarchy, landing on this attachment's
    /// `_HostingEntity` activating) all happening *inside one still-unwinding
    /// `CATransaction`* — a bare MainActor `Task` hop can still land inside
    /// that same reentrant call stack. `SceneEvents.Update` is posted by
    /// RealityKit's own per-frame engine tick, which only runs after the
    /// current transaction has actually committed, so waiting for it (instead
    /// of a fixed number of hops) reliably lands outside that window.
    /// visionOS 27 doesn't hit this at all; the wait is a practically
    /// immediate no-op there, so it's kept unconditionally rather than gated
    /// on OS version.
    @MainActor
    func attachCloseButtonIfNeeded(_ attachments: RealityViewAttachments, content: some RealityViewContentProtocol) {
        guard nameEntity == nil,
              let rootEntity,
              let closeButtonEntity = attachments.entity(for: "NameBarView") else { return }
        nameEntity = closeButtonEntity
        // `[weak rootEntity]`, not `self`, in the subscribe closure itself —
        // mirrors `loadEntity`'s own `manipulationBeganSubscription`/
        // `manipulationEndedSubscription` handlers just below, which hop
        // through an inner `Task { @MainActor in }` before touching `self`
        // rather than capturing this (non-`Sendable`) view struct directly
        // in RealityKit's subscription closure.
        closeButtonAttachSubscription = content.subscribe(to: SceneEvents.Update.self) { [weak rootEntity] _ in
            Task { @MainActor in
                self.closeButtonAttachSubscription?.cancel()
                self.closeButtonAttachSubscription = nil
                guard let rootEntity else { return }
                rootEntity.addChild(closeButtonEntity)
                self.updateCloseButtonPosition()
            }
        }
    }

    /// Keeps the close button just above the object's actual bounding box
    /// (not a flat offset tuned for one size) so it tracks correctly as the
    /// object is dragged, rescaled, or swapped for a differently sized model.
    @MainActor
    func updateCloseButtonPosition() {
        guard let nameEntity, let objectEntity, let rootEntity else { return }
        let bounds = objectEntity.visualBounds(relativeTo: rootEntity)
        nameEntity.position = SIMD3(bounds.center.x, bounds.max.y + 0.08, bounds.center.z)
    }

#endif

    var spaceAccessibilityLabel: Text {
        let name = root.itemController.nameSync(itemId: id)
        return name.isEmpty
            ? Text("3D Model", bundle: .module)
            : Text(verbatim: name)
    }

    func rotate(yawDelta: Float = 0, pitchDelta: Float = 0) {
        withAnimation(reduceMotion ? nil : .spring) {
            yaw += yawDelta
            pitch += pitchDelta
        }
#if os(visionOS)
        // `ManipulationComponent` now owns rotation (see `loadEntity`), so
        // this accessibility action — unlike gesture-driven rotation — has to
        // set the transform directly instead of going through a per-frame
        // yaw/pitch-derived `update:` closure (removed along with `dragRotation`).
        // Same formula that closure used to apply every frame, just now
        // computed on demand from the just-updated yaw/pitch state.
        objectEntity?.transform.rotation = simd_quatf(angle: pitch, axis: .left)
            * simd_quatf(angle: yaw, axis: .upward)
#endif
    }

    func moveObject(x: Float = 0, y: Float = 0, z: Float = 0) {
        guard let objectEntity else { return }
        objectEntity.position += SIMD3(x, y, z)
    }
}

// MARK: - Extracted subviews (CODE_AUDIT §8.3)
//
// Each gives SwiftUI its own diffing boundary, instead of the previous computed
// `some View` properties on `SpaceViewer` itself that all re-evaluated whenever any part
// of `SpaceViewer`'s body did.

private struct SpaceViewerErrorView: View {
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

private struct SpaceViewerProgressView: View {
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
private struct SpaceViewerMovedToImmersiveSpaceView: View {
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
private struct SpaceViewerContentView: View {
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
private struct SpaceViewerPlatformRealityView: View {
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
private struct SpaceViewerCloseButtonView: View {
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
