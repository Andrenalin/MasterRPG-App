// @copyright André Trettin

import CoreRPG
import SwiftUI
import os.log

#if !os(tvOS)
import RealityKit
#if os(visionOS)
import GroupActivities
#endif

struct SpaceViewer: View {
    let root: SpaceRootModel
    let id: UUID
    let isModal: Bool
    var isImmersiveSpace: Bool = false

    var animatableData: AnimatablePair<Float, Float> {
        get {
            .init(yaw, pitch)
        }
        set {
            yaw = newValue.first
            pitch = newValue.second
        }
    }

    @Environment(ScenesManager.self) private var scenesManager

    @Environment(\.dismiss) private var dismiss

    @State private var rootEntity: Entity?
    @State private var objectEntity: Entity?
    @State private var nameEntity: Entity?
    @State private var loadedItemId: UUID?

    @State private var canDrag: Bool = false
    @State private var yaw: Float = .pi / 2
    @State private var pitch: Float = 0
    @State private var hasLoaded: Bool = false
    @State private var loadError: String?

#if os(visionOS)
    // Shared immersive space (SharePlay): placement and manipulation sync.
    @Environment(\.immersiveSpaceDisplacement) private var immersiveSpaceDisplacement
    @Environment(\.networkActions) private var networkActions

    @State private var lastSentTransform: SpaceTransformModel?
    @State private var isSharedPlacement = false
#endif

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottomLeading) {
                if let loadError {
                    errorView(message: loadError)
                } else {
                    progressView

                    contentView(geometry: proxy)

                    spaceContentView
                }
            }
        }
        .applyIf(isModal) {
            $0.toolbar {
#if os(visionOS)
                ToolbarItem(placement: .automatic) {
                    Toggle(isOn: $canDrag) {
                        Label {
                            Text("Move", bundle: .module)
                        } icon: {
                            Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                        }
                    }
                    .tint(root.config.module.tint)
                }

//                ToolbarSpacer()
#endif
            }
        }
#if os(visionOS)
        .immersiveSpaceTracker()  // ✅ Track immersive space lifecycle for ScenesManager
        .onChange(of: immersiveSpaceDisplacement) {
            // The system sets a displacement when it aligns the immersive space
            // for SharePlay — move the model from the head anchor to the shared origin.
            applySharedPlacementIfNeeded()
        }
        .onChange(of: root.gameController.spaceGameModel.sharedTransform) { _, newValue in
            apply(remote: newValue)
        }
        .task(id: hasLoaded) {
            await sendTransformLoop()
        }
#endif
    }
}

#if os(visionOS)
// MARK: - Shared immersive space synchronization

private extension SpaceViewer {
    /// Re-anchors the model from the local head pose to the immersive space
    /// origin, which the system aligns across all SharePlay participants.
    @MainActor
    func applySharedPlacementIfNeeded() {
        guard isImmersiveSpace, immersiveSpaceDisplacement != .identity, !isSharedPlacement else { return }
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
        // Only apply when the shared world origin is established — before that,
        // incoming positions are in the sender's head-local space and will jump.
        guard isImmersiveSpace, isSharedPlacement, let transform, let objectEntity else { return }
        guard transform != lastSentTransform else { return }  // echo of our own send

        yaw = transform.yaw
        pitch = transform.pitch
        objectEntity.position = transform.position
        objectEntity.scale = transform.scale
    }

    /// Broadcasts local manipulations (drag / magnify / rotate) on the game
    /// control channel, throttled so a gesture in progress streams updates.
    @MainActor
    func sendTransformLoop() async {
        guard isImmersiveSpace, hasLoaded, networkActions != nil else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(50))
            sendTransformIfChanged()
        }
    }

    @MainActor
    func sendTransformIfChanged() {
        // Only send after the shared world origin is established — before that,
        // objectEntity.position is relative to the head anchor and remote
        // participants (already in world space) would see the object jump.
        guard isSharedPlacement, let objectEntity else { return }
        let current = SpaceTransformModel(position: objectEntity.position, scale: objectEntity.scale, yaw: yaw, pitch: pitch)
        guard lastSentTransform != nil else {
            // Baseline after load — don't broadcast the initial pose.
            lastSentTransform = current
            return
        }
        // Skip when nothing changed or when the current pose is one we just
        // received from another participant.
        guard current != lastSentTransform, current != root.gameController.spaceGameModel.sharedTransform else { return }
        lastSentTransform = current
        guard let data = current.encodeData() else { return }
        networkActions?.game(NetworkCodableDataType(id: id, type: .space, version: 0, data: data), .spaceTransform, nil)
    }
}
#endif

private extension SpaceViewer {
    var progressView: some View {
        ProgressView()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .progressViewStyle(.circular)
            .opacity(hasLoaded ? 0 : 1)
    }

    func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.red)
            Text("Failed to Load 3D Model", bundle: .module)
                .font(.headline)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    func contentView(geometry: GeometryProxy) -> some View {
        RealityView { content in
            await loadEntity(into: content)
#if !os(visionOS)
            // content here is RealityViewContent (concrete), which exposes cameraTarget.
            // loadEntity receives only RealityViewContentProtocol so it can't set this.
            if let entity = objectEntity {
                content.cameraTarget = entity
            }
#endif
        } update: { content in
            // Only update if entity is loaded and valid
            guard let objectEntity, loadedItemId == id else { return }

#if os(visionOS)
//            this is we activate later
//            let model = objectEntity
//
//            /// The volume's dimensions in local coordinates.
//            let viewBounds = content.convert(
//                geometry.frame(in: .local),
//                from: .local,
//                to: .scene
//            )
//
//            // Set the model's position to the bottom of the visual bounding box.
//            model.position.y -= model.visualBounds(relativeTo: nil).min.y
//
//            // Adjust the model's position on the y-axis to align with the view bounds.
//            model.position.y += viewBounds.min.y
//
//            /// The base size of the model when the scale is 1.
//            let baseExtents = model.visualBounds(relativeTo: nil).extents / model.scale
//
//            /// The scale required for the model to fit the bounds of the volumetric window.
//            let scale = (Float(viewBounds.extents.x) / baseExtents.x) / 4.0
//
//            // Apply the scale to the model to fill the full size of the window.
//            model.scale = SIMD3<Float>(repeating: scale)

#endif

#if os(visionOS)
            objectEntity.transform.rotation = .init(angle: pitch, axis: .left) *
                .init(angle: yaw, axis: .upward)

            if let nameEntity {
                // Use world-space position: nameEntity lives in a separate RealityView
                // scene and setPosition(relativeTo:) across scenes is unsupported.
                nameEntity.position = objectEntity.position(relativeTo: nil) + SIMD3<Float>(0, 2, 0)
            }
#endif
        }
#if os(visionOS)
        .installGestures(canDrag)
        .dragRotation(yaw: $yaw, pitch: $pitch, sensitivity: 3, disableRotation: canDrag)
#else
        // installGestures is visionOS-only: its DragGesture/MagnifyGesture targeted to
        // entities steal from .orbit — orbit handles both rotation and zoom natively.
        .realityViewCameraControls(.orbit)
#endif
    }

    @MainActor
    func loadEntity(into content: some RealityViewContentProtocol) async {
        // Prevent reloading same model
        guard loadedItemId != id else { return }

        do {
            guard let url = await root.itemController.loadableUrl(itemId: id) else {
                loadError = "Failed to get loadable URL for item: \(id)"
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
                loadError = "Loaded model appears to be empty"
                hasLoaded = true
                return
            }

            // Use loadedEntity directly as root on all platforms.
            // The old 100 m container box caused the virtual camera to auto-zoom out to
            // frame the entire container, making the actual model appear tiny inside it.
            let newRootEntity = loadedEntity
            self.objectEntity = loadedEntity

            // Configure interaction on the first mesh entity on all platforms.
            // This keeps hit-testing sized to the actual model, not an oversized proxy.
            if let firstMesh = loadedEntity.firstModelEntity {
                firstMesh.components.set(InputTargetComponent())

                var gestureComponent = GestureComponent()
                gestureComponent.pivotOnDrag = false
                firstMesh.components.set(gestureComponent)
                firstMesh.components.set(HoverEffectComponent(.shader(.default)))
                firstMesh.components.set(GroundingShadowComponent(castsShadow: true))

                // Generate collision shapes asynchronously to avoid blocking Metal
                Task.detached(priority: .utility) {
                    await MainActor.run {
                        firstMesh.generateCollisionShapes(recursive: false, static: true)
                    }
                }
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

            // Shift the entity so its visual centre sits at the world origin.
            // Most USDZ files have their pivot at the base/feet; without this the orbit
            // camera targets the feet and zooming in shows only the bottom of the model.
            let visualCenter = loadedEntity.visualBounds(relativeTo: nil).center

#if os(visionOS)
            if isImmersiveSpace {
                // Hard-coded world coords fail when the user has moved since the ARKit
                // session started — the entity ends up far away and invisible.
                // Apple pattern (HeadTracking sample): anchor to head with trackingMode=.once
                // which world-locks the entity at the current head position.
                let headAnchor = AnchorEntity(.head)
                headAnchor.anchoring.trackingMode = .once
                // Combine centering offset with 2 m in front of the head anchor.
                loadedEntity.position = SIMD3(-visualCenter.x, -visualCenter.y, -visualCenter.z - 2.0)
                headAnchor.addChild(loadedEntity)
                content.add(headAnchor)
                self.rootEntity = headAnchor
                // If the system already aligned the space for SharePlay (joining an
                // active group immersion), move straight to the shared origin.
                applySharedPlacementIfNeeded()
            } else {
                loadedEntity.position = -visualCenter
                content.add(newRootEntity)
                self.rootEntity = newRootEntity
            }
#else
            loadedEntity.position = -visualCenter
            content.add(newRootEntity)
            self.rootEntity = newRootEntity
#endif

            self.loadedItemId = id

        } catch let error as DecodingError {
            loadError = "Model format error: \(error.localizedDescription)"
            print("Decoding error loading 3D entity: \(error)")
        } catch {
            loadError = "Failed to load model: \(error.localizedDescription)"
            print("Error loading 3D entity from URL: \(error)")
        }

        hasLoaded = true
    }

    @ViewBuilder
    var spaceContentView: some View {
#if os(visionOS)
        if let rootEntity {
            RealityView { content, attachments in
                guard let nameBarView = attachments.entity(for: "NameBarView") else {
                    return
                }
                // Position name bar above the root entity in world space.
                // Do NOT call rootEntity.addChild(nameBarView) — rootEntity lives in a
                // different RealityView scene and cross-scene addChild corrupts both scenes.
                let worldPos = rootEntity.position(relativeTo: nil)
                nameBarView.position = worldPos + SIMD3(x: 0, y: 0.7, z: 0)
                nameEntity = nameBarView
                content.add(nameBarView)
            } attachments: {
                Attachment(id: "NameBarView") {
                    Button {
                        Task {
                            await scenesManager.dismissSpaceViewer()
                        }
                    } label: {
                        Label {
                            Text(root.itemController.nameSync(itemId: id))
                        } icon: {
                            Image(systemName: "xmark")
                        }
                    }
                    .frame(width: 250, height: 60, alignment: .center)
                    .padding(20)
                    .glassBackgroundEffect()
                }
            }
        }
#else
        EmptyView()
#endif
    }
}

extension View {
    /// Enables people to drag an entity to rotate it, with optional limitations
    /// on the rotation in yaw and pitch.
    func dragRotation(
        yaw: Binding<Float>,
        pitch: Binding<Float>,
        yawLimit: Angle? = nil,
        pitchLimit: Angle? = nil,
        sensitivity: Float = 10,
        disableRotation: Bool = false,
        disableBackPosition: Bool = true,
        axRotateClockwise: Bool = false,
        axRotateCounterClockwise: Bool = false
    ) -> some View {
        modifier(
            DragRotationModifier(
                yaw: yaw,
                pitch: pitch,
                yawLimit: yawLimit,
                pitchLimit: pitchLimit,
                sensitivity: sensitivity,
                axRotateClockwise: axRotateClockwise,
                axRotateCounterClockwise: axRotateCounterClockwise,
                disableRotation: disableRotation,
                disableBackPosition: disableBackPosition,
                baseYaw: yaw.wrappedValue,
                basePitch: pitch.wrappedValue
            )
        )
    }
}

/// A modifier converts drag gestures into entity rotation.
private struct DragRotationModifier: ViewModifier {
    @Binding var yaw: Float
    @Binding var pitch: Float

    var yawLimit: Angle?
    var pitchLimit: Angle?

    var sensitivity: Float
    var axRotateClockwise: Bool
    var axRotateCounterClockwise: Bool
    var disableRotation: Bool
    var disableBackPosition: Bool

    @State var baseYaw: Float
    @State var basePitch: Float

    func body(content: Content) -> some View {
        content
            .simultaneousGesture(DragGesture(minimumDistance: 0.0)
                .targetedToAnyEntity()
                .onChanged { value in
                    guard disableRotation == false else { return }
                    // Find the current linear displacement.
                    let location3D = value.locationInScene()
                    let startLocation3D = value.startLocationInScene()

                    let delta = location3D - startLocation3D

                    // Use an interactive spring animation that becomes
                    // a spring animation when the gesture ends below.
                    withAnimation(.interactiveSpring) {
                        yaw = spin(displacement: delta.x, base: baseYaw, limit: yawLimit)
                        pitch = spin(displacement: -delta.y, base: basePitch, limit: pitchLimit)
                    }
                }
                .onEnded { value in
                    guard disableRotation == false else { return }

                    if !disableBackPosition {
                        // Find the current and predicted final linear displacements.

                        let location3D = value.locationInScene()
                        let startLocation3D = value.startLocationInScene()
                        let predictedEndLocation3D = value.predictedEndLocationInScene()
                        let delta = location3D - startLocation3D
                        let predictedDelta = predictedEndLocation3D - location3D

                        // Set the final spin value using a spring animation.
                        withAnimation(.spring) {
                            yaw = finalSpin(
                                displacement: delta.x,
                                predictedDisplacement: predictedDelta.x,
                                base: baseYaw,
                                limit: yawLimit)
                            pitch = finalSpin(
                                displacement: -delta.y,
                                predictedDisplacement: -predictedDelta.y,
                                base: basePitch,
                                limit: pitchLimit)
                        }
                    }
                    // Store the last value for use by the next gesture.
                    baseYaw = yaw
                    basePitch = pitch
                }
            )
            .onChange(of: axRotateClockwise) {
                withAnimation(.spring) {
                    yaw -= (.pi / 6)
                    baseYaw = yaw
                }
            }
            .onChange(of: axRotateCounterClockwise) {
                withAnimation(.spring) {
                    yaw += (.pi / 6)
                    baseYaw = yaw
                }
            }
    }

    /// Finds the spin for the specified linear displacement, subject to an
    /// optional limit.
    private func spin(
        displacement: Float,
        base: Float,
        limit: Angle?
    ) -> Float {
        if let limit {
            return atan(displacement * sensitivity) * Float(limit.degrees / 90)
        } else {
            return base + displacement * sensitivity
        }
    }

    /// Finds the final spin given the current and predicted final linear
    /// displacements, or zero when restricting the spin.
    private func finalSpin(
        displacement: Float,
        predictedDisplacement: Float,
        base: Float,
        limit: Angle?
    ) -> Float {
        // If there is a spin limit, always return to zero spin at the end.
        guard limit == nil else { return 0 }

        // Find the projected final linear displacement, capped at 1 more revolution.
        let cap = .pi * 2.0 / sensitivity
        let delta = displacement + max(-cap, min(cap, predictedDisplacement))

        // Find the final spin.
        return base + delta * sensitivity
    }

}

extension ModelEntity {
    func size() -> SIMD3<Float> {
        guard let mesh = self.model?.mesh else {
            return .zero
        }

        let width = mesh.bounds.max.x - mesh.bounds.min.x
        let height = mesh.bounds.max.y - mesh.bounds.min.y
        let depth = mesh.bounds.max.z - mesh.bounds.min.z
        return [width, height, depth]
    }
}

extension Entity {
    var firstModelEntity: ModelEntity? {
        var nextChild = children.first
        while nextChild != nil {
            if let model = nextChild as? ModelEntity {
                return model
            }
            nextChild = nextChild?.children.first
        }
        return nil
    }
}

#if os(visionOS)
// Note: SharePlay synchronization is handled at the GameRPG layer when opening
// the immersive space, not here. SpaceViewer is a generic module and should not
// depend on game-specific SharePlay logic.
#endif

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

    @MainActor
    func predictedEndLocationInScene() -> SIMD3<Float> {
#if os(visionOS)
        return convert(self.predictedEndLocation3D, from: .local, to: .scene)
#else
        if let (origin, direction) = ray(through: self.predictedEndLocation, in: .local, to: .scene) {
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
