// @copyright André Trettin

#if os(visionOS)
import CoreRPG
import Combine
import RealityKit
import SwiftUI

public struct ImmersivePhotoView: View {
    let root: PhotoRootModel

    @State private var photoSelection: PhotoWorldSelection
    @State private var destinationChanged = false

    public init(root: PhotoRootModel, photoSelection: PhotoWorldSelection) {
        self.root = root
        self._photoSelection = State(wrappedValue: photoSelection)
    }

    public var body: some View {
        RealityView { content in
            let rootEntity = Entity()
            content.add(rootEntity)

            // Load texture asynchronously
            Task {
                await rootEntity.loadSkybox(root: root, for: photoSelection)
                destinationChanged = true
            }
        } update: { content in
            guard destinationChanged else { return }
            guard let entity = content.entities.first else { return }

            Task {
                await entity.updateTexture(root: root, for: photoSelection)
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
    @MainActor
    func loadSkybox(root: PhotoRootModel, for photoSelection: PhotoWorldSelection) async {
        do {
            guard let url = await root.itemController.loadableUrl(itemId: photoSelection.id) else {
                print("Failed to get URL for photo selection: \(photoSelection.id)")
                return
            }

            guard let texture = try? await TextureResource(contentsOf: url) else {
                print("Failed to load texture from URL: \(url)")
                return
            }

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
    }

    @MainActor
    func updateTexture(root: PhotoRootModel, for photoSelection: PhotoWorldSelection) async {
        do {
            guard let url = await root.itemController.loadableUrl(itemId: photoSelection.id) else {
                print("Failed to get URL for photo selection: \(photoSelection.id)")
                return
            }

            guard let texture = try? await TextureResource(contentsOf: url) else {
                print("Failed to load texture from URL: \(url)")
                return
            }

            // If ModelComponent doesn't exist, create it
            guard var modelComponent = self.components[ModelComponent.self] else {
                var material = UnlitMaterial()
                material.color = .init(texture: .init(texture))
                self.components.set(ModelComponent(
                    mesh: .generateSphere(radius: 1E3),
                    materials: [material]
                ))
                self.scale *= .init(x: -1, y: 1, z: 1)
                self.transform.translation += SIMD3<Float>(0.0, 1.0, 0.0)
                updateRotation(for: photoSelection)
                return
            }

            // Update existing ModelComponent
            var material = UnlitMaterial()
            material.color = .init(texture: .init(texture))
            modelComponent.materials = [material]
            self.components.set(modelComponent)
            updateRotation(for: photoSelection)
        }
    }

    func updateRotation(for photoSelection: PhotoWorldSelection) {
        // Rotate the immersive space around the Y-axis set the user's
        // initial view of the immersive scene.
        let angle = Angle.degrees(photoSelection.rotationDegrees)
        let rotation = simd_quatf(angle: Float(angle.radians), axis: SIMD3<Float>(0, 1, 0))
        self.transform.rotation = rotation
    }
}

#Preview {
    ImmersivePhotoView(root: .preview, photoSelection: PhotoWorldSelection.empty)
}

#endif
