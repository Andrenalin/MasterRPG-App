// @copyright André Trettin

import CoreRPG
import RealityKit
import SwiftUI

enum Spatial3DImageState {
    case notGenerated
    case generating
    case generated
}

@MainActor @Observable final class ImagePresentationModel {
    var selectedItemId: UUID?

    var imageIndex: Int = 0
    var imageURL: URL? = nil
    var imageAspectRatio: CGFloat = 1.0
    var contentEntity: Entity = Entity()
    var spatial3DImageState: Spatial3DImageState = .notGenerated
    var spatial3DImage: ImagePresentationComponent.Spatial3DImage? = nil

    func createImagePresentationComponent(root: PhotoRootModel) async {
        guard let selectedItemId, let url = await root.itemController.loadableUrl(itemId: selectedItemId) else {
            print("ImageURL is nil.")
            return
        }

        _ = url.startAccessingSecurityScopedResource()
        defer { url.stopAccessingSecurityScopedResource() }
        
        spatial3DImageState = .notGenerated
        spatial3DImage = nil
        do {
            spatial3DImage = try await ImagePresentationComponent.Spatial3DImage(contentsOf: url)
        } catch {
            print("Unable to initialize spatial 3D image: \(error.localizedDescription)")
        }

        guard let spatial3DImage else {
            print("Spatial3DImage is nil.")
            return
        }
        
        let imagePresentationComponent = ImagePresentationComponent(spatial3DImage: spatial3DImage)
        contentEntity.components.set(imagePresentationComponent)
        if let aspectRatio = imagePresentationComponent.aspectRatio(for: .mono) {
            imageAspectRatio = CGFloat(aspectRatio)
        }
    }

    func generateSpatial3DImage() async throws {
        guard spatial3DImageState == .notGenerated else {
            print("Spatial 3D image already generated or generation is in progress.")
            return
        }
        guard let spatial3DImage else {
            print("createImagePresentationComponent.")
            return
        }
        guard var imagePresentationComponent = contentEntity.components[ImagePresentationComponent.self] else {
            print("ImagePresentationComponent is missing from the entity.")
            return
        }
        // Set the desired viewing mode before generating so that it will trigger the
        // generation animation.
        imagePresentationComponent.desiredViewingMode = .spatialStereo
        contentEntity.components.set(imagePresentationComponent)
        
        // Generate the Spatial3DImage scene.
        spatial3DImageState = .generating
        try await spatial3DImage.generate()
        spatial3DImageState = .generated

        if let aspectRatio = imagePresentationComponent.aspectRatio(for: .spatialStereo) {
            imageAspectRatio = CGFloat(aspectRatio)
        }
    }
}
