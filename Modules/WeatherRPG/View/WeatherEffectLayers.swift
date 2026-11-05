// @copyright André Trettin

import CoreRPG
import SwiftUI

/// The weather drawn over its photo: stars, clouds, lightning and the storm's rain or snow.
/// The 2D viewers stack them flat. On visionOS the 3D weather window sets `layerSpacing` so
/// each layer sits nearer the viewer than the one behind it, in front of the spatial photo.
struct WeatherEffectLayers: View {
    let model: WeatherModel
    let lightningTrigger: Int
    /// The depth between two layers, in points toward the viewer. Zero stacks them flat.
    var layerSpacing: CGFloat = 0

    var body: some View {
        ZStack {
            StarsView()
                .opacity(starOpacity)

            CloudsView(
                thickness: model.cloudThickness,
                topTint: WeatherViewer.cloudTopStops.interpolated(amount: model.time),
                bottomTint: WeatherViewer.cloudBottomStops.interpolated(amount: model.time)
            )
            .weatherLayerDepth(layerSpacing)

            LightningView(
                frequency: model.lightningFrequency,
                maximumBolts: WeatherLimits.count(model.lightningMaxBolts, in: WeatherLimits.lightningMaxBolts),
                forkProbability: WeatherLimits.count(model.lightningForkProbability, in: WeatherLimits.lightningForkProbability),
                trigger: lightningTrigger
            )
            .weatherLayerDepth(layerSpacing * 2)

            if model.stormType != .none {
                StormView(
                    type: model.stormType,
                    direction: .degrees(model.rainAngle),
                    strength: WeatherLimits.count(model.rainIntensity, in: WeatherLimits.rainIntensity)
                )
                .weatherLayerDepth(layerSpacing * 3)
            }
        }
    }

    private var starOpacity: Double {
        WeatherViewer.starStops.interpolated(amount: model.time).getComponents().alpha
    }
}

private extension View {
    /// Moves a weather layer toward the viewer on visionOS; elsewhere the layers stay flat.
    @ViewBuilder
    func weatherLayerDepth(_ depth: CGFloat) -> some View {
#if os(visionOS)
        offset(z: depth)
#else
        self
#endif
    }
}
