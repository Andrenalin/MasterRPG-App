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
    
#if os(visionOS)
    @Environment(WindowStateModel.self) private var windowStateModel
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
#endif
    
    @Environment(\.dismiss) private var dismiss
    
    @State private var rootEntity = Entity()
    @State private var objectEntity = Entity()
    @State private var nameEntity = Entity()
    
    @State private var canDrag: Bool = false
    @State private var yaw: Float = .pi / 2
    @State private var pitch: Float = 0
    @State private var hasLoaded: Bool = false
    
    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottomLeading) {
                progressView
                
                contentView
                
                spaceContentView
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
    
    var contentView: some View {
        RealityView { content in
            do {
                guard let url = await root.itemController.loadableUrl(for: ItemRowModel(itemId: id, typeId: root.itemController.config.module)) else { return }
                
                defer { url.stopAccessingSecurityScopedResource() }
                let _ = url.startAccessingSecurityScopedResource()
                
                let objectEntity = try await Entity(contentsOf: url, withName: "3DMaster")
                self.objectEntity = objectEntity
                
#if os(visionOS)
                rootEntity = objectEntity
#else
                rootEntity = ModelEntity(mesh: .generateBox(size: valueFor(iOS: 100, macOS: 100, tvOS: 100, visionOS: 10)))
                rootEntity.addChild(objectEntity)
#endif
                
                if let firstMesh = objectEntity.firstModelEntity {
                    let inputObject = valueFor(iOS: rootEntity, macOS: rootEntity, tvOS: rootEntity, visionOS: firstMesh)
                    inputObject.components.set(InputTargetComponent())
                    var gestureComponent = GestureComponent()
                    gestureComponent.pivotOnDrag = false
                    inputObject.components.set(gestureComponent)
                    inputObject.components.set(HoverEffectComponent(.shader(.default)))
                    inputObject.components.set(GroundingShadowComponent(castsShadow: true))
                    inputObject.generateCollisionShapes(recursive: false, static: true)
                    
                    let rootSize = firstMesh.size()
                    
                    let maxSize = max(rootSize.z, max(rootSize.x, rootSize.y))
                    let minScaleF = (1 / maxSize)
                    objectEntity.scale *= minScaleF
                }
#if os(visionOS)
                objectEntity.position = SIMD3(x: 0, y: 1, z: -2)
#else
                objectEntity.position = SIMD3(x: 0, y: 0, z: 0)
                content.camera = .virtual
#endif
                content.add(rootEntity)
            } catch {
                print(error)
            }
            hasLoaded = true
        } update: { content in
            objectEntity.transform.rotation = .init(angle: pitch, axis: .left) *
                .init(angle: yaw, axis: .upward)
            nameEntity.setPosition([0, 2, 0], relativeTo: objectEntity)
        }
        .installGestures(canDrag)
#if !os(visionOS)
        .dragRotation(yaw: $yaw, pitch: $pitch, sensitivity: 3, disableRotation: canDrag)
#endif
    }
    
    @ViewBuilder
    var spaceContentView: some View {
#if os(visionOS)
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
                    windowStateModel.spaceImmersiveView = false
                    Task {
                        await dismissImmersiveSpace()
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
