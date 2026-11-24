// @copyright André Trettin

import CoreRPG
import SwiftUI

/// The weather drawn over its photo: stars, clouds, lightning and the storm's rain or snow.
/// The 2D viewers stack them flat. On visionOS the 3D weather window sets `layerSpacing` so
/// each layer sits nearer the viewer than the one behind it, in front of the spatial photo.
struct WeatherEffectLayers: View {
    let model: WeatherModel
    let lightningTrigger: Int
    /// A strike another device shared.
    var incomingBolt: LightningBoltSpec? = nil
    /// Called when a tap on the lightning layer starts a strike.
    var onLightningTap: ((LightningBoltSpec) -> Void)? = nil
    /// Whether a tap on the lightning layer strikes.
    var isLightningTapEnabled = true
    /// The depth between two layers, in points toward the viewer. Zero stacks them flat.
    var layerSpacing: CGFloat = 0

    var body: some View {
        ZStack {
            // Not part of the stack while it cannot be seen: a layer faded to zero still ran its
            // timeline and drew every frame. See CODE_AUDIT_26 §7.20.
            if starOpacity > 0 {
                StarsView()
                    .opacity(starOpacity)
                    .allowsHitTesting(false)
            }

            if model.cloudThickness != .none {
                CloudsView(
                    thickness: model.cloudThickness,
                    topTint: WeatherViewer.cloudTopStops.interpolated(amount: model.time),
                    bottomTint: WeatherViewer.cloudBottomStops.interpolated(amount: model.time)
                )
                .weatherLayerDepth(layerSpacing)
                .allowsHitTesting(false)
            }

            LightningView(
                frequency: model.lightningFrequency,
                maximumBolts: WeatherLimits.count(model.lightningMaxBolts, in: WeatherLimits.lightningMaxBolts),
                forkProbability: WeatherLimits.count(model.lightningForkProbability, in: WeatherLimits.lightningForkProbability),
                trigger: lightningTrigger,
                incomingBolt: incomingBolt,
                onTap: onLightningTap,
                isTapEnabled: isLightningTapEnabled
            )
            .weatherLayerDepth(layerSpacing * 2)

            if model.stormType != .none {
                StormView(
                    type: model.stormType,
                    direction: .degrees(model.rainAngle),
                    strength: WeatherLimits.count(model.rainIntensity, in: WeatherLimits.rainIntensity)
                )
                .weatherLayerDepth(layerSpacing * 3)
                // Drawn above the lightning: it must not take the tap meant for it.
                .allowsHitTesting(false)
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
