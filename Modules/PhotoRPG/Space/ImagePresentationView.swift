// @copyright André Trettin

import RealityKit
import SwiftUI
import CoreRPG

#if os(visionOS)
import UIKit

struct ImagePresentationView: View {
    let model: ImagePresentationModel
    
    @Environment(PhotoRootModel.self) private var root
    @Environment(AppNavigationModel.self) private var navigationModel

    var body: some View {
        GeometryReader3D { geometry in
            RealityView { content in
                await model.createImagePresentationComponent(root: root)
                // Scale the entity to fit in the bounds.
                let availableBounds = content.convert(geometry.frame(in: .local), from: .local, to: .scene)
                scaleImagePresentationToFit(in: availableBounds)
                content.add(model.contentEntity)
            } update: { content in
                guard let presentationScreenSize = model
                    .contentEntity
                    .observable
                    .components[ImagePresentationComponent.self]?
                    .presentationScreenSize, presentationScreenSize != .zero else {
                        print("Unable to get a valid presentation screen size from the content entity.")
                        return
                }
                // Position the entity at the back of the window.
                let originalPosition = model.contentEntity.position(relativeTo: nil)
                model.contentEntity.setPosition(SIMD3<Float>(originalPosition.x, originalPosition.y, 0.0), relativeTo: nil)
                // Scale the entity to fit in the bounds.
                let availableBounds = content.convert(geometry.frame(in: .local), from: .local, to: .scene)
                scaleImagePresentationToFit(in: availableBounds)
            }
            .onAppear() {
                guard let windowScene = navigationModel.sceneModel?.windowScene else {
                    print("Unable to get the window scene. Unable to set the resizing restrictions.")
                    return
                }
                // Ensure that the scene resizes uniformly on X and Y axes.
                windowScene.requestGeometryUpdate(.Vision(resizingRestrictions: .uniform))
            }
            .onChange(of: model.imageAspectRatio) { _, newAspectRatio in
                guard let windowScene = navigationModel.sceneModel?.windowScene else {
                    print("Unable to get the window scene. Resizing is not possible.")
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
            .onChange(of: model.selectedItemId) {
                Task {
                    await model.createImagePresentationComponent(root: root)
                }
            }
        }
        .aspectRatio(model.imageAspectRatio, contentMode: .fit)
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

        model.contentEntity.scale = SIMD3<Float>(scale, scale, 1.0)
    }
}

#endif
