// @copyright André Trettin

#if os(visionOS)
import CoreRPG
import RealityKit
import SwiftUI
import os.log

extension Logger {
    static let photoSpace = Logger(subsystem: subsystem, category: "PhotoSpace")
}

enum Spatial3DImageState {
    case notGenerated
    case generating
    case generated
}

@MainActor @Observable public final class ImagePresentationModel {
    /// The photo shown. Each window showing a spatial photo needs its own model: its
    /// `contentEntity` can be in only one `RealityView`.
    public var selectedItemId: UUID?

    public init() {}

    /// Whether the photo is being converted to spatial 3D. The ornament is hidden meanwhile.
    public var isGeneratingSpatial3DImage: Bool {
        spatial3DImageState == .generating
    }

    var imageAspectRatio: CGFloat = 1.0
    var contentEntity: Entity = Entity()
    /// The view's foreground attachment, in front of the photo. Set by `ImagePresentationView`.
    @ObservationIgnored var foregroundEntity: Entity?
    /// The invisible input target over the foreground that receives its taps. Added to the
    /// foreground entity by `ImagePresentationView` when the foreground takes taps.
    @ObservationIgnored let foregroundTapTarget: Entity = {
        let target = Entity()
        target.name = ImagePresentationModel.foregroundTapTargetName
        target.components.set(InputTargetComponent())
        return target
    }()
    static let foregroundTapTargetName = "ForegroundTapTarget"
    /// Keeps the foreground from being placed again on frames where nothing moved it.
    @ObservationIgnored var foregroundPlacementGate = ForegroundPlacementGate()
    var spatial3DImageState: Spatial3DImageState = .notGenerated
    var spatial3DImage: ImagePresentationComponent.Spatial3DImage? = nil

    func createImagePresentationComponent(root: PhotoRootModel) async {
        guard let requestedItemId = selectedItemId else {
            return
        }

        // Reset synchronously for this selection. No state is mutated by this
        // load after an await until the selected item is validated again.
        spatial3DImageState = .notGenerated
        spatial3DImage = nil

        guard let url = await root.itemController.loadableUrl(itemId: requestedItemId),
              !Task.isCancelled,
              selectedItemId == requestedItemId else {
            Logger.photoSpace.error("ImageURL is nil.")
            return
        }

        let securityScope = url.startSecurityScopedAccess()
        defer { securityScope.stop() }
        
        let loadedSpatial3DImage: ImagePresentationComponent.Spatial3DImage
        do {
            loadedSpatial3DImage = try await ImagePresentationComponent.Spatial3DImage(contentsOf: url)
        } catch {
            Logger.photoSpace.error("Unable to initialize spatial 3D image: \(error.logIdentifier, privacy: .public) \(error.localizedDescription, privacy: .private)")
            return
        }

        // Ignore a completed load when another received photo has replaced it.
        guard !Task.isCancelled, selectedItemId == requestedItemId else {
            return
        }

        spatial3DImage = loadedSpatial3DImage
        let imagePresentationComponent = ImagePresentationComponent(spatial3DImage: loadedSpatial3DImage)
        contentEntity.components.set(imagePresentationComponent)
        if let aspectRatio = imagePresentationComponent.aspectRatio(for: .mono) {
            imageAspectRatio = CGFloat(aspectRatio)
        }
    }

    /// Loads a received photo, converts it, and presents it in spatial 3D.
    func createAndShowSpatial3DImage(root: PhotoRootModel) async {
        await createImagePresentationComponent(root: root)
        guard !Task.isCancelled, spatial3DImageState == .notGenerated, spatial3DImage != nil else {
            return
        }

        do {
            try await generateSpatial3DImage()
        } catch is CancellationError {
            // A new photo superseded this conversion.
        } catch {
            Logger.photoSpace.error("Spatial3DImage generation failed: \(error.logIdentifier, privacy: .public) \(error.localizedDescription, privacy: .private)")
        }
    }

    func generateSpatial3DImage() async throws {
        guard spatial3DImageState == .notGenerated else {
            Logger.photoSpace.debug("Spatial 3D image already generated or generation is in progress.")
            return
        }
        guard let spatial3DImage else {
            Logger.photoSpace.error("generateSpatial3DImage called before createImagePresentationComponent.")
            return
        }
        guard var imagePresentationComponent = contentEntity.components[ImagePresentationComponent.self] else {
            Logger.photoSpace.error("ImagePresentationComponent is missing from the entity.")
            return
        }
        // Set the desired viewing mode before generating so that it will trigger the
        // generation animation.
        imagePresentationComponent.desiredViewingMode = .spatialStereo
        contentEntity.components.set(imagePresentationComponent)
        
        // Generate the Spatial3DImage scene.
        spatial3DImageState = .generating
        do {
            try await spatial3DImage.generate()
        } catch {
            if self.spatial3DImage === spatial3DImage {
                spatial3DImageState = .notGenerated
            }
            throw error
        }

        // A selection change can finish while the old conversion is running.
        guard !Task.isCancelled, self.spatial3DImage === spatial3DImage else {
            return
        }

        spatial3DImageState = .generated

        // Generation begins in spatial stereo to show RealityKit's conversion
        // animation. Once ready, transition directly to the full spatial 3D view.
        imagePresentationComponent.desiredViewingMode = .spatial3D
        contentEntity.components.set(imagePresentationComponent)

        if let aspectRatio = imagePresentationComponent.aspectRatio(for: .spatial3D) {
            imageAspectRatio = CGFloat(aspectRatio)
        }
    }
}

#endif
