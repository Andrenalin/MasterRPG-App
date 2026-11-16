// @copyright André Trettin

import CoreRPG
import os.log
import RealityKit
import SwiftUI

#if !os(tvOS)

extension SpaceViewer {
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
        // This runs from the `RealityView` being made, i.e. one exists now. The 3D scanner
        // can no longer get its camera afterwards. See `SpaceRootModel.liveViewerWasShown`.
        RealityViewPresence.noteCreated()

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
            let securityScope = url.startSecurityScopedAccess()
            defer { securityScope.stop() }

            // RealityKit parses the file on the main actor, so a file far above what the app
            // accepts as a source file would freeze the screen. See CODE_AUDIT_22 §6.5.
            if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > ByteLimits.maximumSourceFileBytes {
                loadError = String(localized: "The 3D model file is too large to show.", bundle: .module)
                hasLoaded = true
                return
            }

            // Load entity from USDZ file
            let loadedEntity = try await Entity(contentsOf: url, withName: "3DMaster")

            // Validate the loaded entity has something to show. Every entity has a transform
            // component, so counting children and components was always true: a USDZ without
            // a mesh never got this message and was positioned from an empty bounding box.
            // See CODE_AUDIT_21 §5.28.
            guard !loadedEntity.visualBounds(relativeTo: nil).isEmpty else {
                loadError = String(localized: "The 3D model is empty.", bundle: .module)
                hasLoaded = true
                return
            }

            // Use loadedEntity directly as root on all platforms.
            // The old 100 m container box caused the virtual camera to auto-zoom out to
            // frame the entire container, making the actual model appear tiny inside it.
            let newRootEntity = loadedEntity
            self.objectEntity = loadedEntity

            configureInteraction(of: loadedEntity, in: content)
            startCollisionShapeGeneration(for: loadedEntity)
            normalizeScale(of: loadedEntity)
            place(loadedEntity, root: newRootEntity, into: content)

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
            if isImmersiveSpace {
                adoptRetainedPoseForTablePlacement()
            }
            #endif

        } catch let error as DecodingError {
            loadError = String(
                localized: "The 3D model format could not be read: \(error.localizedDescription)",
                bundle: .module
            )
            Logger.spaceViewer.error("Decoding error loading 3D entity: \(error.logIdentifier, privacy: .public) \(error.localizedDescription, privacy: .private)")
        } catch {
            loadError = String(
                localized: "The 3D model could not be loaded: \(error.localizedDescription)",
                bundle: .module
            )
            Logger.spaceViewer.error("Error loading 3D entity from URL: \(error.logIdentifier, privacy: .public) \(error.localizedDescription, privacy: .private)")
        }

        hasLoaded = true
    }

    /// Makes the whole loaded hierarchy one hit-testable, draggable unit: the interaction components
    /// go on the root entity (not on one sub-mesh found by walking the first-child chain, which
    /// left multi-part models and single-entity models without any), and collision shapes are
    /// generated recursively.
    @MainActor
    func configureInteraction(of loadedEntity: Entity, in content: some RealityViewContentProtocol) {
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
            ) { [weak loadedEntity, relay = manipulationRelay] event in
                guard event.entity == loadedEntity else { return }
                Task { @MainActor in
                    relay.began?(event.entity)
                }
            }
            manipulationEndedSubscription = content.subscribe(
                to: ManipulationEvents.WillEnd.self
            ) { [weak loadedEntity, relay = manipulationRelay] event in
                guard event.entity == loadedEntity else { return }
                Task { @MainActor in
                    relay.ended?(event.entity)
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
            //
            // Set directly in the (main-actor) handlers, not a turn later through a
            // `Task` hop: a grab in the same turn as a table-placement attempt must
            // already be seen by its `!isManipulating` guard. See CODE_AUDIT_19 §3.16.
            manipulationBeganSubscription = content.subscribe(
                to: ManipulationEvents.WillBegin.self
            ) { [weak loadedEntity, relay = manipulationRelay] event in
                guard event.entity == loadedEntity else { return }
                relay.began?(event.entity)
            }
            manipulationEndedSubscription = content.subscribe(
                to: ManipulationEvents.WillEnd.self
            ) { [weak loadedEntity, relay = manipulationRelay] event in
                guard event.entity == loadedEntity else { return }
                relay.ended?(event.entity)
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
    }

    /// Generates the collision shapes in a cancellable task, so a rapid item switch does not leave
    /// the stale generation running against an entity that may no longer be on screen.
    @MainActor
    func startCollisionShapeGeneration(for loadedEntity: Entity) {
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
    }

    @MainActor
    func normalizeScale(of loadedEntity: Entity) {
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
    }

    /// Puts the entity into the scene: under a head anchor in the immersive space, centred at the
    /// world origin elsewhere.
    @MainActor
    func place(_ loadedEntity: Entity, root newRootEntity: Entity, into content: some RealityViewContentProtocol) {
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
    }

#if os(visionOS)
    /// Adds the close-button attachment as a child of `rootEntity` (the
    /// anchor, not `objectEntity`) the first time both exist. Parenting it —
    /// instead of computing a one-shot world position in a second, separate
    /// `RealityView` scene (the previous approach) — means the button is
    /// governed by the *same* RealityKit scene graph as the model and tracks
    /// automatically as the anchor is re-parented (`applySharedPlacementIfNeeded`)
    /// or the model is dragged, matching `GameTableModel.registerAttachment(_:for:)`'s
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
#else
        // Elsewhere the camera orbits and nothing derives the entity's rotation from yaw/pitch, so
        // the accessibility action turns the entity by the same delta, about the world axes.
        // See CODE_AUDIT_26 §8.34.
        if let objectEntity {
            objectEntity.transform.rotation = simd_quatf(angle: pitchDelta, axis: .left)
                * simd_quatf(angle: yawDelta, axis: .upward)
                * objectEntity.transform.rotation
        }
#endif
    }

    func moveObject(x: Float = 0, y: Float = 0, z: Float = 0) {
        guard let objectEntity else { return }
        objectEntity.position += SIMD3(x, y, z)
    }
}

#endif
