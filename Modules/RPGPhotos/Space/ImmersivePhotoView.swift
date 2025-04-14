// @copyright André Trettin

#if os(visionOS)
import AndrenalinKit
import Combine
import RealityKit
import SwiftUI

public struct ImmersivePhotoView: View {
    let root: PhotoRoot

    @State private var photoSelection: PhotoWorldSelection
    @State private var destinationChanged = false

    public init(root: PhotoRoot, photoSelection: PhotoWorldSelection) {
        self.root = root
        self._photoSelection = State(wrappedValue: photoSelection)
    }

    public var body: some View {
        RealityView { content in
            let rootEntity = Entity()
            rootEntity.addSkybox(root: root, for: photoSelection)
            content.add(rootEntity)
            destinationChanged = true
        } update: { content in
            guard destinationChanged else { return }
            guard let entity = content.entities.first else { fatalError() }
            entity.updateTexture(root: root, for: photoSelection)
            Task { @MainActor in
                destinationChanged = false
            }
        }
        .onChange(of: root.gameController.photoGameModel.currentSelection) { oldValue, newValue in
            if let newValue, photoSelection != newValue {
                photoSelection = newValue
                destinationChanged = true
            }
        }
        .transition(.opacity)
    }
}

extension Entity {
    func addSkybox(root: PhotoRoot, for photoSelection: PhotoWorldSelection) {
        let subscription = Task {
            guard let url = await root.itemController.loadableUrl(for: ItemRowModel(itemId: photoSelection.id, typeId: .photo)) else { return }
            guard let texture = try? await TextureResource(contentsOf: url) else { return }
            
            var material = UnlitMaterial()
            material.color = .init(texture: .init(texture))
            self.components.set(ModelComponent(
                mesh: .generateSphere(radius: 1E3),
                materials: [material]
            ))
            self.scale *= .init(x: -1, y: 1, z: 1)
            self.transform.translation += SIMD3<Float>(0.0, 1.0, 0.0)
            
            // Rotate the sphere to show the best initial view of the space.
            updateRotation(for: photoSelection)
        }
        components.set(Entity.SubscriptionComponent(subscription: subscription))
    }

    func updateTexture(root: PhotoRoot, for photoSelection: PhotoWorldSelection) {
        let subscription = Task {
            guard let url = await root.itemController.loadableUrl(for: ItemRowModel(itemId: photoSelection.id, typeId: .photo)) else { return }
            guard let texture = try? await TextureResource(contentsOf: url) else { return }
            guard var modelComponent = self.components[ModelComponent.self] else {
                var material = UnlitMaterial()
                material.color = .init(texture: .init(texture))
                self.components.set(ModelComponent(
                    mesh: .generateSphere(radius: 1E3),
                    materials: [material]
                ))
                self.scale *= .init(x: -1, y: 1, z: 1)
                self.transform.translation += SIMD3<Float>(0.0, 1.0, 0.0)

                return
//                fatalError("Should have already a Model Component!")
            }

            var material = UnlitMaterial()
            material.color = .init(texture: .init(texture))
            modelComponent.materials = [material]
            self.components.set(modelComponent)
            updateRotation(for: photoSelection)
        }
        components.set(Entity.SubscriptionComponent(subscription: subscription))
    }

    func updateRotation(for photoSelection: PhotoWorldSelection) {
        // Rotate the immersive space around the Y-axis set the user's
        // initial view of the immersive scene.
        let angle = Angle.degrees(photoSelection.rotationDegrees)
        let rotation = simd_quatf(angle: Float(angle.radians), axis: SIMD3<Float>(0, 1, 0))
        self.transform.rotation = rotation
    }

    struct SubscriptionComponent: Component {
        var subscription: Task<(), Never>
    }
}

#Preview {
    ImmersivePhotoView(root: .preview, photoSelection: PhotoWorldSelection.empty)
}

#endif
