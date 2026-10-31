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
    @Environment(\.accessibilityDimFlashingLights) private var accessibilityDimFlashingLights
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    @State private var lightningTrigger = 0
    @State private var animationTrace: PerformanceTrace.Interval?

    /// Shared "time of day" keyframe schedule for every gradient below, so the
    /// day/night timing can only be tuned in one place. See CODE_AUDIT_Weather §9.2.
    private enum DayKeyframe {
        static let midnightStart = 0.0
        static let midnightHold = 0.25
        static let sunriseStart = 0.33
        static let sunriseEnd = 0.38
        static let sunsetStart = 0.7
        static let sunsetEnd = 0.78
        static let midnightReturn = 0.82
        static let midnightEnd = 1.0

        static let locations: [Double] = [
            midnightStart, midnightHold, sunriseStart, sunriseEnd,
            sunsetStart, sunsetEnd, midnightReturn, midnightEnd,
        ]

        static func stops(_ colors: [Color]) -> [Gradient.Stop] {
            precondition(colors.count == locations.count)
            return zip(locations, colors).map { .init(color: $1, location: $0) }
        }
    }

    static let backgroundTopStops: [Gradient.Stop] = DayKeyframe.stops([
        .midnightStart, .midnightStart, .sunriseStart, .sunnyDayStart,
        .sunnyDayStart, .sunsetStart, .midnightStart, .midnightStart,
    ])

    static let backgroundBottomStops: [Gradient.Stop] = DayKeyframe.stops([
        .midnightEnd, .midnightEnd, .sunriseEnd, .sunnyDayEnd,
        .sunnyDayEnd, .sunsetEnd, .midnightEnd, .midnightEnd,
    ])

    static let cloudTopStops: [Gradient.Stop] = DayKeyframe.stops([
        .darkCloudStart, .darkCloudStart, .sunriseCloudStart, .lightCloudStart,
        .lightCloudStart, .sunsetCloudStart, .darkCloudStart, .darkCloudStart,
    ])

    static let cloudBottomStops: [Gradient.Stop] = DayKeyframe.stops([
        .darkCloudEnd, .darkCloudEnd, .sunriseCloudEnd, .lightCloudEnd,
        .lightCloudEnd, .sunsetCloudEnd, .darkCloudEnd, .darkCloudEnd,
    ])

    static let starStops: [Gradient.Stop] = DayKeyframe.stops([
        .white, .white, .clear, .clear,
        .clear, .clear, .white, .white,
    ])

    var starOpacity: Double {
        let color = Self.starStops.interpolated(amount: model.time)
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
                    topTint: Self.cloudTopStops.interpolated(amount: model.time),
                    bottomTint: Self.cloudBottomStops.interpolated(amount: model.time)
                )
                
                LightningView(
                    frequency: model.lightningFrequency,
                    maximumBolts: WeatherLimits.count(model.lightningMaxBolts, in: WeatherLimits.lightningMaxBolts),
                    forkProbability: WeatherLimits.count(model.lightningForkProbability, in: WeatherLimits.lightningForkProbability),
                    trigger: lightningTrigger
                )
                
                if model.stormType != .none {
                    StormView(type: model.stormType, direction: .degrees(model.rainAngle), strength: WeatherLimits.count(model.rainIntensity, in: WeatherLimits.rainIntensity))
                }
            }
        }
        .frame(width: containerSize.width, height: containerSize.height)
        .background {
            LinearGradient(colors: [
                Self.backgroundTopStops.interpolated(amount: model.time),
                Self.backgroundBottomStops.interpolated(amount: model.time),
            ], startPoint: .top, endPoint: .bottom)
        #if !os(macOS)
            .ignoresSafeArea(.container)
        #endif
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Weather preview for \(model.name)", bundle: .module))
        .accessibilityValue(Text(verbatim: accessibilitySummary))
        .accessibilityAddTraits(.isImage)
        .accessibilityActions {
            if canTriggerLightning {
                Button {
                    PerformanceTrace.event("WeatherLightningTriggered")
                    lightningTrigger &+= 1
                } label: {
                    Text("Trigger Lightning", bundle: .module)
                }
            }
        }
        .onAppear {
            updatePerformanceTrace(isActive: isAnimating || useGame)
        }
        .onChange(of: isAnimating) { _, isAnimating in
            updatePerformanceTrace(isActive: isAnimating || useGame)
        }
        .onDisappear {
            animationTrace?.end()
            animationTrace = nil
            isAnimating = false
        }
    }

    private func updatePerformanceTrace(isActive: Bool) {
        if isActive, animationTrace == nil {
            animationTrace = PerformanceTrace.begin(
                "WeatherAnimationVisible",
                source: "WeatherViewer",
                count: model.stormType == .none ? 3 : 4
            )
        } else if !isActive {
            animationTrace?.end()
            animationTrace = nil
        }
    }

    var containerSize: CGSize {
        CGSize(width: size.width > 0 ? size.width : 320, height: size.height > 0 ? size.height : 64)
    }

    private var accessibilitySummary: String {
        let start = Calendar.current.startOfDay(for: .now)
        let time = start
            .addingTimeInterval(model.time * 24 * 60 * 60)
            .formatted(date: .omitted, time: .shortened)
        let clouds = String(localized: model.cloudThickness.localizedTitle)
        let precipitation = String(localized: model.stormType.localizedTitle)
        let intensity = model.rainIntensity.formatted(
            .number.precision(.fractionLength(0))
        )
        let lightning = model.lightningFrequency.formatted(
            .number.precision(.fractionLength(0))
        )

        return String(
            localized: "Time: \(time); Clouds: \(clouds); Precipitation: \(precipitation); Intensity: \(intensity); Lightning: \(lightning) per minute",
            bundle: .module
        )
    }

    private var canTriggerLightning: Bool {
        (isAnimating || useGame)
        && !accessibilityReduceMotion
        && !accessibilityDimFlashingLights
    }
}

#Preview {
    @Previewable @State var isAnimating = false
    WeatherViewer(model: .heavy, size: CGSize(width: 375, height: 375), useGame: false, isAnimating: $isAnimating)
        .environment(WeatherRootModel.preview)
}
