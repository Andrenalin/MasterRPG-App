// @copyright André Trettin

#if os(visionOS)

import RealityKit
import SwiftUI
import CoreRPG
import UIKit
import os.log

struct ImagePresentationView: View {
    let model: ImagePresentationModel

    @Environment(PhotoRootModel.self) private var root
    @Environment(AppNavigationModel.self) private var navigationModel

    /// Keeps the entity's position/scale synced to the window on every
    /// RealityKit-rendered frame, not only when SwiftUI happens to
    /// re-invoke `RealityView`'s `update` closure. `update` only fires when
    /// `GeometryReader3D`'s geometry or another observed dependency changes
    /// — a window that has stopped being dragged produces no such change, so
    /// the entity is left frozen on whatever transform the *last* frame of
    /// the drag produced. On visionOS 26.5, `content.convert(...)` can
    /// momentarily report degenerate bounds mid-drag (the same class of
    /// RealityKit-engine-timing issue already worked around in
    /// `SpaceViewer.attachCloseButtonIfNeeded` — see that method's own doc);
    /// freezing on one of those frames scales/positions the spatial-3D image
    /// outside its valid parallax viewing volume, so RealityKit renders
    /// nothing there and `UserSettingsViewModifier`'s `theme.backgroundGradient`
    /// (sitting behind this `RealityView` in the window) shows through as a
    /// black gradient. `SceneEvents.Update` is posted by RealityKit's own
    /// per-frame engine tick, so resyncing there can't get stuck on a stale
    /// SwiftUI-driven frame the way `update` alone can.
    @State private var sceneUpdateSubscription: EventSubscription?

    /// Feeds `syncPresentation()` calls triggered by `sceneUpdateSubscription` to a
    /// single long-lived consumer `Task` instead of spawning a fresh unstructured
    /// `Task` on every RealityKit engine tick (~90Hz on visionOS) — see that
    /// subscription's own doc. `.bufferingNewest(1)` coalesces bursts of ticks into
    /// the latest signal rather than queuing every one. See CODE_AUDIT §7.1.
    @State private var frameSyncContinuation: AsyncStream<Void>.Continuation?
    @State private var frameSyncTask: Task<Void, Never>?

    /// The window's bounds in RealityKit scene space, refreshed synchronously
    /// from `content.convert(...)` inside `make`/`update` — `content` there
    /// is an `inout` parameter, so it can't be captured by the escaping
    /// `SceneEvents.Update` closure. Caching the converted bounds instead
    /// lets that per-frame closure rescale the entity without needing
    /// `content` at all.
    @State private var lastAvailableBounds: BoundingBox?

    var body: some View {
        GeometryReader3D { geometry in
            RealityView { content in
                // Scale the entity to fit in the bounds.
                let availableBounds = content.convert(geometry.frame(in: .local), from: .local, to: .scene)
                scaleImagePresentationToFit(in: availableBounds)
                cacheAvailableBounds(availableBounds)
                content.add(model.contentEntity)
                // `SceneEvents.Update` isn't MainActor-isolated, and
                // `model.contentEntity` lives on `model`'s `@MainActor`
                // isolation — hop through the coalescing stream above before
                // touching it, mirroring `SpaceViewer.attachCloseButtonIfNeeded`'s
                // own subscription for the same reason.
                let (stream, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
                frameSyncContinuation = continuation
                frameSyncTask = Task { @MainActor in
                    for await _ in stream {
                        syncPresentation()
                    }
                }
                sceneUpdateSubscription = content.subscribe(to: SceneEvents.Update.self) { _ in
                    continuation.yield()
                }
            } update: { content in
                let availableBounds = content.convert(geometry.frame(in: .local), from: .local, to: .scene)
                syncPresentation(boundsInMeters: availableBounds)
                cacheAvailableBounds(availableBounds)
            }
            .task(id: model.selectedItemId) {
                await model.createAndShowSpatial3DImage(root: root)
            }
            .onAppear {
                guard let windowScene = navigationModel.sceneModel?.windowScene else {
                    Logger.photoSpace.error("Unable to get the window scene. Unable to set the resizing restrictions.")
                    return
                }
                // Ensure that the scene resizes uniformly on X and Y axes.
                windowScene.requestGeometryUpdate(.Vision(resizingRestrictions: .uniform))
            }
            .onDisappear {
                // The RealityKit subscription keeps firing (and holding the content) until it
                // is cancelled. See CODE_AUDIT_18 §3.19.
                sceneUpdateSubscription?.cancel()
                sceneUpdateSubscription = nil
                frameSyncContinuation?.finish()
                frameSyncTask?.cancel()
            }
            .onChange(of: model.imageAspectRatio) { _, newAspectRatio in
                guard let windowScene = navigationModel.sceneModel?.windowScene else {
                    Logger.photoSpace.error("Unable to get the window scene. Resizing is not possible.")
                    return
                }

                let windowSceneSize = windowScene.effectiveGeometry.coordinateSpace.bounds.size

                //  width / height = aspect ratio
                // Change ONLY the width to match the aspect ratio.
                let width = newAspectRatio * windowSceneSize.height

                // Keep the height the same.
                let size = CGSize(width: width, height: UIProposedSceneSizeNoPreference)

                UIView.performWithoutAnimation {
                    // Update the scene size.
                    windowScene.requestGeometryUpdate(.Vision(size: size))
                }
            }
        }
        .aspectRatio(model.imageAspectRatio, contentMode: .fit)
    }
    
    /// Positions the entity at the back of the window and rescales it to fit
    /// `boundsInMeters`, called from both the `update` closure and the
    /// per-frame `SceneEvents.Update` subscription so the two stay in sync —
    /// see `sceneUpdateSubscription`'s doc for why the subscription exists.
    /// `update` passes the bounds it just computed directly so this frame
    /// isn't left waiting on `cacheAvailableBounds`'s deferred write; the
    /// per-frame subscription (which has no fresh value of its own) omits it
    /// and falls back to the cached `lastAvailableBounds`.
    func syncPresentation(boundsInMeters: BoundingBox? = nil) {
        guard let presentationScreenSize = model
            .contentEntity
            .observable
            .components[ImagePresentationComponent.self]?
            .presentationScreenSize, presentationScreenSize != .zero else {
                return
            }
        // Position the entity at the back of the window.
        let originalPosition = model.contentEntity.position(relativeTo: nil)
        model.contentEntity.setPosition(SIMD3<Float>(originalPosition.x, originalPosition.y, 0.0), relativeTo: nil)
        // Scale the entity to fit in the bounds.
        guard let boundsInMeters = boundsInMeters ?? lastAvailableBounds else {
            return
        }
        scaleImagePresentationToFit(in: boundsInMeters)
    }

    /// Caches `bounds` into `lastAvailableBounds` for the per-frame
    /// `SceneEvents.Update` subscription to read back later — see that
    /// property's own doc. Deferred through a `Task` rather than assigned
    /// directly: `RealityView`'s `make`/`update` closures run synchronously
    /// as part of SwiftUI's own view-update pass, and writing straight to
    /// `@State` there trips "Modifying state during view update, this will
    /// cause undefined behavior." Both call sites already have the fresh
    /// value in hand and pass it straight to `scaleImagePresentationToFit`/
    /// `syncPresentation` instead of relying on the cache for their own
    /// frame, so the one-tick delay here only affects later reads.
    func cacheAvailableBounds(_ bounds: BoundingBox) {
        Task {
            lastAvailableBounds = bounds
        }
    }

    /// Fit the image presentation inside a bounding box by scaling the content entity.
    func scaleImagePresentationToFit(in boundsInMeters: BoundingBox) {
        guard let imagePresentationComponent = model.contentEntity.components[ImagePresentationComponent.self] else {
            return
        }

        let presentationScreenSize = imagePresentationComponent.presentationScreenSize
        let scale = min(
            boundsInMeters.extents.x / presentationScreenSize.x,
            boundsInMeters.extents.y / presentationScreenSize.y
        )
        // A mid-drag frame on visionOS 26.5 can hand back a degenerate
        // (zero/NaN) bounding box for one tick; applying that as the
        // entity's scale would freeze the spatial-3D image outside its valid
        // viewing volume until the next real update. Skip it and keep
        // whatever scale was last valid instead.
        guard scale.isFinite, scale > 0 else {
            return
        }

        model.contentEntity.scale = SIMD3<Float>(scale, scale, 1.0)
    }
}

#Preview(traits: .mockData) {
    ImagePresentationView(model: ImagePresentationModel())
}

#endif
