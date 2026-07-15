// @copyright André Trettin

import CoreRPG
import SwiftUI
import PhotoRPG

struct WeatherViewer: View {
    let model: WeatherModel
    let size: CGSize
    let useGame: Bool
    @Binding var isAnimating: Bool

    @Environment(WeatherRootModel.self) private var root

    let backgroundTopStops: [Gradient.Stop] = [
        .init(color: .midnightStart, location: 0),
        .init(color: .midnightStart, location: 0.25),
        .init(color: .sunriseStart, location: 0.33),
        .init(color: .sunnyDayStart, location: 0.38),
        .init(color: .sunnyDayStart, location: 0.7),
        .init(color: .sunsetStart, location: 0.78),
        .init(color: .midnightStart, location: 0.82),
        .init(color: .midnightStart, location: 1),
    ]

    let backgroundBottomStops: [Gradient.Stop] = [
        .init(color: .midnightEnd, location: 0),
        .init(color: .midnightEnd, location: 0.25),
        .init(color: .sunriseEnd, location: 0.33),
        .init(color: .sunnyDayEnd, location: 0.38),
        .init(color: .sunnyDayEnd, location: 0.7),
        .init(color: .sunsetEnd, location: 0.78),
        .init(color: .midnightEnd, location: 0.82),
        .init(color: .midnightEnd, location: 1),
    ]

    let cloudTopStops: [Gradient.Stop] = [
        .init(color: .darkCloudStart, location: 0),
        .init(color: .darkCloudStart, location: 0.25),
        .init(color: .sunriseCloudStart, location: 0.33),
        .init(color: .lightCloudStart, location: 0.38),
        .init(color: .lightCloudStart, location: 0.7),
        .init(color: .sunsetCloudStart, location: 0.78),
        .init(color: .darkCloudStart, location: 0.82),
        .init(color: .darkCloudStart, location: 1),
    ]

    let cloudBottomStops: [Gradient.Stop] = [
        .init(color: .darkCloudEnd, location: 0),
        .init(color: .darkCloudEnd, location: 0.25),
        .init(color: .sunriseCloudEnd, location: 0.33),
        .init(color: .lightCloudEnd, location: 0.38),
        .init(color: .lightCloudEnd, location: 0.7),
        .init(color: .sunsetCloudEnd, location: 0.78),
        .init(color: .darkCloudEnd, location: 0.82),
        .init(color: .darkCloudEnd, location: 1),
    ]

    let starStops: [Gradient.Stop] = [
        .init(color: .white, location: 0),
        .init(color: .white, location: 0.25),
        .init(color: .clear, location: 0.33),
        .init(color: .clear, location: 0.38),
        .init(color: .clear, location: 0.7),
        .init(color: .clear, location: 0.78),
        .init(color: .white, location: 0.82),
        .init(color: .white, location: 1),
    ]

    var starOpacity: Double {
        let color = starStops.interpolated(amount: model.time)
        return color.getComponents().alpha
    }

    var body: some View {
        ZStack {
            if let photoId = model.photoId {
                root.photoRoot.viewController.photoDetailView(root: root.photoRoot, for: photoId, size: containerSize, contentMode: .fill)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }

            if isAnimating || useGame {
                StarsView()
                    .opacity(starOpacity)
                
                CloudsView(
                    thickness: model.cloudThickness,
                    topTint: cloudTopStops.interpolated(amount: model.time),
                    bottomTint: cloudBottomStops.interpolated(amount: model.time)
                )
                
                LightningView(frequency: model.lightningFrequency, maximumBolts: Int(model.lightningMaxBolts), forkProbability: Int(model.lightningForkProbability))
                
                if model.stormType != .none {
                    StormView(type: model.stormType, direction: .degrees(model.rainAngle), strength: Int(model.rainIntensity))
                }
            }
        }
        .frame(width: containerSize.width, height: containerSize.height)
        .background {
            LinearGradient(colors: [
                backgroundTopStops.interpolated(amount: model.time),
                backgroundBottomStops.interpolated(amount: model.time),
            ], startPoint: .top, endPoint: .bottom)
        #if !os(macOS)
            .ignoresSafeArea(.container)
        #endif
        }
        .frame(width: containerSize.width, height: containerSize.height)
        .onDisappear {
            isAnimating = false
        }
    }

    var containerSize: CGSize {
        CGSize(width: size.width > 0 ? size.width : 320, height: size.height > 0 ? size.height : 64)
    }
}

#Preview {
    @Previewable @State var isAnimating = false
    WeatherViewer(model: .heavy, size: CGSize(width: 375, height: 375), useGame: false, isAnimating: $isAnimating)
        .environment(WeatherRootModel.preview)
}
