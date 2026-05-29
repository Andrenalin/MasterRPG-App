// @copyright André Trettin

import CoreRPG
import SwiftUI

#if !os(tvOS)
import RealityKit

struct SpaceViewer: View {
    let root: SpaceRootModel
    let id: UUID
    let isModal: Bool

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
#if !os(visionOS)
                ToolbarItem(placement: .automatic) {
                    Toggle(isOn: $canDrag) {
                        Label {
                            Text("Move", bundle: .module)
                        } icon: {
                            Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                        }
                    }
#if os(macOS)
                .foregroundStyle(root.config.module.tint)
#else
                .tint(root.config.module.tint)
#endif
                }

                ToolbarSpacer()
#endif
            }
        }
    }
}

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

            objectEntity.transform.rotation = .init(angle: pitch, axis: .left) *
                .init(angle: yaw, axis: .upward)

            if let nameEntity {
                nameEntity.setPosition([0, 2, 0], relativeTo: objectEntity)
            }
        }
        .installGestures(canDrag)
#if !os(visionOS)
        .dragRotation(yaw: $yaw, pitch: $pitch, sensitivity: 3, disableRotation: canDrag)
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

#if os(visionOS)
            let newRootEntity = loadedEntity
            self.objectEntity = loadedEntity
#else
            // Create container entity for non-visionOS platforms
            let container = ModelEntity(mesh: .generateBox(size: valueFor(iOS: 100, macOS: 100, tvOS: 100, visionOS: 10)))
            container.addChild(loadedEntity)
            let newRootEntity = container
            self.objectEntity = loadedEntity
#endif

            // Configure entity for interaction
            if let firstMesh = loadedEntity.firstModelEntity {
                let inputObject = valueFor(iOS: newRootEntity, macOS: newRootEntity, tvOS: newRootEntity, visionOS: firstMesh)
                inputObject.components.set(InputTargetComponent())

                var gestureComponent = GestureComponent()
                gestureComponent.pivotOnDrag = false
                inputObject.components.set(gestureComponent)
                inputObject.components.set(HoverEffectComponent(.shader(.default)))
                inputObject.components.set(GroundingShadowComponent(castsShadow: true))

                // Generate collision shapes asynchronously to avoid blocking Metal
                Task.detached(priority: .utility) {
                    await MainActor.run {
                        inputObject.generateCollisionShapes(recursive: false, static: true)
                    }
                }
            }

            // Normalize scale using full visual bounds so intermediate transforms and
            // multi-mesh hierarchies are measured correctly (mesh-local bounds alone miss this).
            let visualBounds = loadedEntity.visualBounds(relativeTo: loadedEntity)
            let maxExtent = max(visualBounds.extents.x, max(visualBounds.extents.y, visualBounds.extents.z))
            if maxExtent > 0.001 && maxExtent.isFinite {
                let targetSize: Float = valueFor(iOS: 1.0, macOS: 1.0, tvOS: 1.0, visionOS: 0.5)
                loadedEntity.scale *= targetSize / maxExtent
            }

            // visionOS: origin is the centre of the volumetric window — keep the entity there.
            // z: -2 would place it 2 m outside the volume bounds and make it invisible.
            loadedEntity.position = .zero
#if !os(visionOS)
            if var cameraContent = content as? RealityViewCameraContent {
                cameraContent.camera = .virtual
            }
#endif

            // Only add to scene if all setup succeeded
            content.add(newRootEntity)
            self.rootEntity = newRootEntity
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
                nameBarView.setPosition([0, 2, 2], relativeTo: rootEntity)
                nameEntity = nameBarView
                rootEntity.addChild(nameBarView)
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

#endif
