// @copyright André Trettin

#if os(visionOS)

import RealityKit
import SwiftUI
import CoreRPG
import UIKit
import os.log

struct ImagePresentationView<Foreground: View>: View {
    let model: ImagePresentationModel
    /// Drawn in front of the photo over its whole area, such as a weather. A RealityView
    /// attachment, placed in front of the photo's nearest point: a SwiftUI overlay sits on the
    /// window's plane, and the spatial photo's depth covers it there.
    let foreground: Foreground
    /// `false` for the plain photo window: it then has no attachment and nothing to place.
    /// See CODE_AUDIT_24 §7.1.
    private let hasForeground: Bool
    /// Called when the foreground is tapped; `nil` leaves it without a tap target. The tap is a
    /// RealityKit input target over the photo, not a SwiftUI control in the attachment: the
    /// attachment is a texture on a plane in the photo's scene, and a control in it does not
    /// receive the pinch the scene's own entities take.
    private let onForegroundTap: (() -> Void)?

    init(model: ImagePresentationModel, foreground: Foreground, onForegroundTap: (() -> Void)? = nil) {
        self.init(model: model, foreground: foreground, hasForeground: true, onForegroundTap: onForegroundTap)
    }

    fileprivate init(model: ImagePresentationModel, foreground: Foreground, hasForeground: Bool, onForegroundTap: (() -> Void)? = nil) {
        self.model = model
        self.foreground = foreground
        self.hasForeground = hasForeground
        self.onForegroundTap = onForegroundTap
    }

    @Environment(PhotoRootModel.self) private var root
    @Environment(AppNavigationModel.self) private var navigationModel

    /// Keeps the entity's position/scale synced to the window on every RealityKit-rendered
    /// frame, not only when SwiftUI re-invokes `RealityView`'s `update` closure: a window that
    /// has stopped being dragged produces no such change, so the entity would stay on whatever
    /// transform the last frame of the drag produced. On visionOS 26.5 `content.convert(...)`
    /// can momentarily report degenerate bounds mid-drag; freezing on one of those frames
    /// scales/positions the spatial-3D image outside its valid parallax viewing volume, so
    /// RealityKit renders nothing there and the theme gradient behind this view shows through.
    /// `SceneEvents.Update` is posted by RealityKit's own per-frame tick, so resyncing there
    /// cannot get stuck on a stale SwiftUI-driven frame. It runs while the view is visible: it
    /// stops on disappear and the `update` closure starts it again on appear.
    @State private var frameSync = ImagePresentationFrameSync()

    /// The window's bounds in RealityKit scene space, refreshed synchronously
    /// from `content.convert(...)` inside `make`/`update` — `content` there
    /// is an `inout` parameter, so it can't be captured by the escaping
    /// `SceneEvents.Update` closure. Caching the converted bounds instead
    /// lets that per-frame closure rescale the entity without needing
    /// `content` at all.
    @State private var lastAvailableBounds: BoundingBox?

    var body: some View {
        GeometryReader3D { geometry in
            RealityView { content, attachments in
                // Scale the entity to fit in the bounds.
                let availableBounds = content.convert(geometry.frame(in: .local), from: .local, to: .scene)
                scaleImagePresentationToFit(in: availableBounds)
                cacheAvailableBounds(availableBounds)
                content.add(model.contentEntity)
                model.foregroundPlacementGate.reset()
                if hasForeground, let foregroundEntity = attachments.entity(for: Self.foregroundAttachmentId) {
                    content.add(foregroundEntity)
                    model.foregroundEntity = foregroundEntity
                    placeForeground(in: availableBounds)
                }
                frameSync.start(content: &content) { syncPresentation() }
            } update: { content, attachments in
                let availableBounds = content.convert(geometry.frame(in: .local), from: .local, to: .scene)
                // Reading `isVisible` makes SwiftUI call this closure again on appear: the sync was
                // stopped on disappear and `make` does not run again.
                if frameSync.isVisible, frameSync.needsRestart {
                    frameSync.start(content: &content) { syncPresentation() }
                    if hasForeground, model.foregroundEntity == nil,
                       let foregroundEntity = attachments.entity(for: Self.foregroundAttachmentId) {
                        if foregroundEntity.parent == nil {
                            content.add(foregroundEntity)
                        }
                        model.foregroundEntity = foregroundEntity
                    }
                }
                syncPresentation(boundsInMeters: availableBounds)
                cacheAvailableBounds(availableBounds)
            } attachments: {
                if hasForeground {
                    Attachment(id: Self.foregroundAttachmentId) {
                        // The window's size: the photo fills it, fitted to its aspect ratio.
                        foreground
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .allowsHitTesting(false)
                    }
                }
            }
            .gesture(
                TapGesture().targetedToAnyEntity().onEnded { value in
                    guard value.entity.name == ImagePresentationModel.foregroundTapTargetName else { return }
                    onForegroundTap?()
                },
                including: onForegroundTap == nil ? .subviews : .all
            )
            .task(id: model.selectedItemId) {
                await model.createAndShowSpatial3DImage(root: root)
            }
            .onAppear {
                frameSync.appeared()
                guard let windowScene = navigationModel.sceneModel?.windowScene else {
                    Logger.photoSpace.error("Unable to get the window scene. Unable to set the resizing restrictions.")
                    return
                }
                // Ensure that the scene resizes uniformly on X and Y axes.
                windowScene.requestGeometryUpdate(.Vision(resizingRestrictions: .uniform))
            }
            .onDisappear {
                frameSync.disappeared()
                model.foregroundEntity = nil
                model.foregroundPlacementGate.reset()
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
        // The foreground follows the photo also while it loads or converts: its depth grows
        // as the conversion runs.
        if hasForeground, let bounds = boundsInMeters ?? lastAvailableBounds {
            placeForeground(in: bounds)
        }
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

    /// Places the foreground over the photo, just in front of the photo's nearest point and
    /// never behind the window's plane.
    func placeForeground(in boundsInMeters: BoundingBox) {
        guard hasForeground, let foregroundEntity = model.foregroundEntity else { return }
        // The bounds traversal below only runs when something that moves the foreground changed.
        let inputs = ForegroundPlacementGate.Inputs(
            windowCenter: boundsInMeters.center,
            windowExtents: boundsInMeters.extents,
            photoScale: model.contentEntity.scale,
            photoScreenSize: model.contentEntity.components[ImagePresentationComponent.self]?
                .presentationScreenSize ?? .zero,
            isPhotoChanging: model.spatial3DImageState != .generated
        )
        guard model.foregroundPlacementGate.needsPlacement(for: inputs) else { return }
        placeForegroundTapTarget(on: foregroundEntity, extents: boundsInMeters.extents)
        let photoBounds = model.contentEntity.visualBounds(relativeTo: nil)
        let photoFront = photoBounds.isEmpty || !photoBounds.max.z.isFinite ? 0 : photoBounds.max.z
        let center = boundsInMeters.center
        guard center.x.isFinite, center.y.isFinite else { return }
        // Never behind the window's plane, and never further out than `foregroundMaximumDepth`,
        // should the photo's bounds report more depth than it shows.
        let front = min(max(photoFront, boundsInMeters.min.z), boundsInMeters.min.z + Self.foregroundMaximumDepth)
        let position = SIMD3<Float>(center.x, center.y, front + Self.foregroundClearance)
        // Runs on every frame: only a real move touches the entity.
        if simd_distance(foregroundEntity.position(relativeTo: nil), position) > 0.0005 {
            foregroundEntity.setPosition(position, relativeTo: nil)
        }
    }

    /// Keeps the tap target, a transparent plane over the whole window just in front of the
    /// foreground, on the foreground entity and as large as the window.
    private func placeForegroundTapTarget(on foregroundEntity: Entity, extents: SIMD3<Float>) {
        guard onForegroundTap != nil, extents.x.isFinite, extents.y.isFinite, extents.x > 0, extents.y > 0 else { return }
        let target = model.foregroundTapTarget
        if target.parent !== foregroundEntity {
            foregroundEntity.addChild(target)
        }
        // In front of the attachment's plane, so the pinch reaches the target first.
        target.position = [0, 0, Self.foregroundTapTargetClearance]
        target.components.set(CollisionComponent(shapes: [
            .generateBox(width: extents.x, height: extents.y, depth: Self.foregroundTapTargetDepth),
        ]))
    }

    private static var foregroundAttachmentId: String { "ImagePresentationForeground" }
    /// The tap target's distance in front of the foreground's plane, in meters.
    private static var foregroundTapTargetClearance: Float { 0.005 }
    /// The tap target's thickness, in meters.
    private static var foregroundTapTargetDepth: Float { 0.002 }
    /// The gap between the photo's nearest point and the foreground, in meters.
    private static var foregroundClearance: Float { 0.01 }
    /// How far the photo's front may push the foreground out of the window, in meters.
    private static var foregroundMaximumDepth: Float { 0.15 }

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

extension ImagePresentationView where Foreground == EmptyView {
    init(model: ImagePresentationModel) {
        self.init(model: model, foreground: EmptyView(), hasForeground: false)
    }
}

#Preview(traits: .mockData) {
    ImagePresentationView(model: ImagePresentationModel())
}

#endif
