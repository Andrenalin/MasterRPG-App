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
    @Environment(\.networkActions) private var networkActions
    @Environment(\.isGamePlayer) private var isGamePlayer

    @State private var incomingBolt: LightningBoltSpec?
    /// Counts the game master's taps: `LightningView` starts a strike for each and shares it.
    @State private var lightningTrigger = 0

    var body: some View {
        if let photoId = model.photoId {
            root.photoRoot.viewController.spatialPhotoView(
                root: root.photoRoot,
                model: presentation,
                onForegroundTap: isGamePlayer ? nil : { lightningTrigger &+= 1 }
            ) {
                // In the photo's RealityKit scene, in front of the photo's depth: a SwiftUI
                // overlay on the window's plane is covered by the spatial photo.
                WeatherEffectLayers(
                    model: model,
                    lightningTrigger: lightningTrigger,
                    incomingBolt: incomingBolt,
                    onLightningTap: shareLightning,
                    isLightningTapEnabled: !isGamePlayer,
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
                .onChange(of: root.receivedLightning) { _, received in
                    guard let strike = received?.strike, strike.weatherId == model.id else { return }
                    incomingBolt = strike.bolt
                }
        } else {
            // Without a photo there is nothing to convert: the weather as the 2D viewer shows it.
            WeatherViewerContainer(model: model, useGame: true, isAnimating: .constant(true))
        }
    }

    /// Shares a strike a tap started with the players. A player's tap is turned off.
    private func shareLightning(_ bolt: LightningBoltSpec) {
        guard let networkActions else { return }
        let strike = WeatherLightningStrike(weatherId: model.id, bolt: bolt)
        networkActions.game(strike.networkData, .generic, nil)
    }
}

#Preview(traits: .mockData) {
    WeatherSpaceView()
}
#endif
