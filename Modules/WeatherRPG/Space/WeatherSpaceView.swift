// @copyright André Trettin

#if os(visionOS)
import CoreRPG
import PhotoRPG
import SwiftUI

/// The visionOS weather window: the weather's photo converted to spatial 3D, as the photo
/// window shows a photo, with the weather's stars, clouds, lightning and rain or snow in
/// front of it at increasing depth.
struct WeatherSpaceView: View {
    @Environment(WeatherRootModel.self) private var root

    var body: some View {
        let space = root.weatherSpaceModel
        if let weatherId = space.selectedItemId {
            WeatherSpaceContent(
                model: root.gameController.gameItem(for: weatherId),
                presentation: space.imagePresentationModel
            )
            .id(weatherId)
        } else {
            ContentUnavailableView {
                Label {
                    Text("No Weather", bundle: .module)
                } icon: {
                    Image(systemName: "cloud.sun")
                }
            }
        }
    }
}

private enum WeatherSpaceLayout {
    /// The depth between two weather layers, in points toward the viewer.
    static let layerSpacing: CGFloat = 24
}

private struct WeatherSpaceContent: View {
    let model: WeatherModel
    let presentation: ImagePresentationModel

    @Environment(WeatherRootModel.self) private var root

    var body: some View {
        if let photoId = model.photoId {
            root.photoRoot.viewController.spatialPhotoView(root: root.photoRoot, model: presentation) {
                // In the photo's RealityKit scene, in front of the photo's depth: a SwiftUI
                // overlay on the window's plane is covered by the spatial photo.
                WeatherEffectLayers(
                    model: model,
                    lightningTrigger: 0,
                    layerSpacing: WeatherSpaceLayout.layerSpacing
                )
                .accessibilityHidden(true)
            }
                .ornament(
                    visibility: presentation.isGeneratingSpatial3DImage ? .hidden : .visible,
                    attachmentAnchor: .scene(.bottomFront)
                ) {
                    root.photoRoot.viewController.spatialPhotoOrnament(model: presentation)
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel(Text("Weather preview for \(model.name)", bundle: .module))
                .task(id: photoId) {
                    // The weather's photo can change while the window is open.
                    if presentation.selectedItemId != photoId {
                        presentation.selectedItemId = photoId
                    }
                }
        } else {
            // Without a photo there is nothing to convert: the weather as the 2D viewer shows it.
            WeatherViewerContainer(model: model, useGame: true, isAnimating: .constant(true))
        }
    }
}

#Preview(traits: .mockData) {
    WeatherSpaceView()
}
#endif
