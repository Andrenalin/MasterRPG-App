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
#endif

    var body: some View {
        ZStack(alignment: .bottomLeading) {
#if os(visionOS)
            if handedOffToImmersive {
                movedToImmersiveSpaceView
            } else if let loadError {
                errorView(message: loadError)
            } else {
                progressView

                contentView
            }
#else
            if let loadError {
                errorView(message: loadError)
            } else {
                progressView

                contentView
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
        if transform == lastSentTransform {
            // The master rebroadcast is the acknowledgement for our optimistic
            // local manipulation. Stop periodic retries without moving the model.
            lastAcknowledgedTransform = transform
            unacknowledgedTransformTicks = 0
            return
        }

        objectEntity.transform.rotation = transform.orientation
        objectEntity.position = transform.position
        objectEntity.scale = transform.scale
        lastAcknowledgedTransform = transform
        unacknowledgedTransformTicks = 0
    }

    /// Broadcasts local manipulations (drag / magnify / rotate) on the game
    /// control channel, throttled so a gesture in progress streams updates.
    @MainActor
    func sendTransformLoop() async {
        guard isImmersiveSpace, hasLoaded, networkActions != nil else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(300))
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
        guard simd_distance(entity.position, start) > 0.15 else { return }
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
            // `openSpaceViewer` silently no-ops if the immersive space is
            // already open or opening — including when it's showing a
            // *different* item, which would otherwise strand this handoff:
            // the entity above is already detached and `pending` in
            // `SpaceHandoffModel`, but nothing would ever open to adopt it.
            // Dismissing first (a no-op if already closed) guarantees the
            // subsequent open always starts from `.closed`, so it reliably
            // succeeds and shows this item instead of silently dropping it.
            await scenesManager.dismissSpaceViewer()
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
    var progressView: some View {
        ProgressView()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .progressViewStyle(.circular)
            .opacity(hasLoaded ? 0 : 1)
            .allowsHitTesting(!hasLoaded)
            .accessibilityHidden(hasLoaded)
    }

    func errorView(message: String) -> some View {
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

#if os(visionOS)
    var movedToImmersiveSpaceView: some View {
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
#endif

    // Split out from `contentView`: the multiple-trailing-closure `RealityView`
    // initializer (three trailing closures on visionOS, once attachments were
    // added) combined with the long `.accessibilityElement`/`.accessibilityAction`
    // chain in one expression was too much for the type checker to solve as a
    // single unit — it reported a spurious "cannot infer contextual base" on
    // `.accessibilityElement` instead of pointing at the real expression.
    // Isolating the `RealityView` construction into its own small `@ViewBuilder`
    // property lets each half type-check independently.
    @ViewBuilder
    private var platformRealityView: some View {
#if os(visionOS)
        RealityView { content, attachments in
            await loadEntity(into: content)
            if isImmersiveSpace {
                attachCloseButtonIfNeeded(attachments)
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
                attachCloseButtonIfNeeded(attachments)
                nameEntity?.isEnabled = showCloseButton
                updateCloseButtonPosition()
            }
        } attachments: {
            if isImmersiveSpace {
                Attachment(id: "NameBarView") {
                    closeButton
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
            await loadEntity(into: content)
            // content here is RealityViewContent (concrete), which exposes cameraTarget.
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

    var contentView: some View {
        platformRealityView
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spaceAccessibilityLabel)
        .accessibilityValue(
            Text(
                "Yaw \(Angle.radians(Double(yaw)).degrees, format: .number.precision(.fractionLength(0))) degrees, pitch \(Angle.radians(Double(pitch)).degrees, format: .number.precision(.fractionLength(0))) degrees",
                bundle: .module
            )
        )
        .accessibilityAction(named: Text("Rotate Left", bundle: .module)) {
            rotate(yawDelta: -.pi / 6)
        }
        .accessibilityAction(named: Text("Rotate Right", bundle: .module)) {
            rotate(yawDelta: .pi / 6)
        }
        .accessibilityAction(named: Text("Tilt Up", bundle: .module)) {
            rotate(pitchDelta: .pi / 12)
        }
        .accessibilityAction(named: Text("Tilt Down", bundle: .module)) {
            rotate(pitchDelta: -.pi / 12)
        }
        .accessibilityAction(named: Text("Move Left", bundle: .module)) {
            moveObject(x: -0.1)
        }
        .accessibilityAction(named: Text("Move Right", bundle: .module)) {
            moveObject(x: 0.1)
        }
        .accessibilityAction(named: Text("Move Up", bundle: .module)) {
            moveObject(y: 0.1)
        }
        .accessibilityAction(named: Text("Move Down", bundle: .module)) {
            moveObject(y: -0.1)
        }
        .accessibilityAction(named: Text("Move Forward", bundle: .module)) {
            moveObject(z: 0.1)
        }
        .accessibilityAction(named: Text("Move Backward", bundle: .module)) {
            moveObject(z: -0.1)
        }
    }

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
            // drag/rotate/scale component — it replaces the hand-rolled
            // `GestureComponent` + `installGestures`/`dragRotation` gesture
            // plumbing entirely for this platform: no SwiftUI `.gesture()` is
            // wired up anywhere for it (see `platformRealityView`). It sets
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

            // Window-embedded instance only: watch `ManipulationComponent`'s
            // own event stream (not a second gesture — see the "drag is gone"
            // history on `moveToImmersiveSpace`) to detect "dragged far
            // enough" and hand the object off to the immersive space.
            if !isImmersiveSpace {
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
            }
#else
            loadedEntity.components.set(InputTargetComponent())

            var gestureComponent = GestureComponent()
            gestureComponent.pivotOnDrag = false
            loadedEntity.components.set(gestureComponent)
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
            let targetSize: Float = isImmersiveSpace ? 1.0 : 0.5
#else
            let targetSize: Float = 0.5
#endif
            let baseExtents = loadedEntity.visualBounds(relativeTo: nil).extents / loadedEntity.scale
            let maxBase = max(baseExtents.x, max(baseExtents.y, baseExtents.z))
            if maxBase > 0.0001 && maxBase.isFinite {
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
    @MainActor
    func attachCloseButtonIfNeeded(_ attachments: RealityViewAttachments) {
        guard nameEntity == nil,
              let rootEntity,
              let closeButtonEntity = attachments.entity(for: "NameBarView") else { return }
        rootEntity.addChild(closeButtonEntity)
        nameEntity = closeButtonEntity
        updateCloseButtonPosition()
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

    var closeButton: some View {
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

#if os(visionOS)
// Note: SharePlay synchronization is handled at the GameRPG layer when opening
// the immersive space, not here. SpaceViewer is a generic module and should not
// depend on game-specific SharePlay logic.
#endif

// Used by `EntityGestureState.handleFixedDrag`'s non-visionOS branch (the
// `GestureComponent`-driven drag, which nothing wires up via a SwiftUI
// gesture on macOS/iOS/tvOS — see the `#else` branch of `platformRealityView`
// — but the code still has to compile). Left in place rather than removed
// along with `DragRotationModifier`, which was this extension's other user.
extension EntityTargetValue<DragGesture.Value> {
    @MainActor
    func locationInScene() -> SIMD3<Float> {
#if os(visionOS)
        return convert(self.location3D, from: .local, to: .scene)
#else
        if let (origin, direction) = ray(through: self.location, in: .local, to: .scene) {
            return origin + length(entity.position - origin) * direction
        }
        return .zero
#endif
    }

    @MainActor
    func startLocationInScene() -> SIMD3<Float> {
#if os(visionOS)
        return convert(self.startLocation3D, from: .local, to: .scene)
#else
        if let (origin, direction) = ray(through: self.startLocation, in: .local, to: .scene) {
            return origin + length(entity.position - origin) * direction
        }
        return .zero
#endif
    }
}

#Preview("Space Viewer") {
    SpaceViewer(root: .preview, id: SpaceModel.previewId, isModal: false)
        .environment(ScenesManager())
}

#endif
