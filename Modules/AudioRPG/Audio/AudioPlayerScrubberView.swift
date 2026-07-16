// @copyright André Trettin

import SwiftUI

#Preview {
    AudioPlayerScrubberView(currentTime: 92, totalDuration: 245, elapsedText: "01:32", onSeek: { _ in })
        .padding()
}

struct AudioPlayerScrubberView: View {
    let currentTime: Double
    let totalDuration: Double
    let elapsedText: String
    let onSeek: @Sendable (Double) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(verbatim: elapsedText)
                .font(.caption2)
                .foregroundStyle(.primary)
                .monospacedDigit()
                .frame(minWidth: 38)
                .accessibilityLabel(Text("Elapsed Time", bundle: .module))

#if !os(tvOS)
            Slider(
                value: Binding(
                    get: { clampedCurrentTime },
                    set: onSeek
                ),
                in: sliderRange
            )
            .tint(.primary)
            .accessibilityLabel(Text("Playback Position", bundle: .module))
            .accessibilityValue(accessibilityTimeValue)
#endif

            Text(verbatim: formattedTotalTime)
                .font(.caption2)
                .foregroundStyle(.primary)
                .monospacedDigit()
                .frame(minWidth: 38)
                .accessibilityLabel(Text("Total Duration", bundle: .module))
        }
    }

    private var sliderRange: ClosedRange<Double> {
        // Ensure valid, positive range with minimum of 1 second
        let safeDuration = max(totalDuration.isFinite ? totalDuration : 1, 1)
        return 0...safeDuration
    }

    private var clampedCurrentTime: Double {
        // Clamp current time to valid range
        let safeDuration = max(totalDuration.isFinite ? totalDuration : 1, 1)
        let safeTime = currentTime.isFinite ? currentTime : 0
        return min(max(safeTime, 0), safeDuration)
    }

    private var formattedTotalTime: String {
        formatTime(totalDuration)
    }

    private var accessibilityTimeValue: Text {
        Text(
            "\(Int(clampedCurrentTime.rounded())) seconds of \(Int(sliderRange.upperBound.rounded())) seconds",
            bundle: .module
        )
    }

    private func formatTime(_ time: Double) -> String {
        guard !time.isNaN && time.isFinite else { return "--:--" }

        let totalSeconds = Int(ceil(max(time, 0)))
        let hours = totalSeconds / 3600
        let pattern: Duration.TimeFormatStyle.Pattern = hours > 0
            ? .hourMinuteSecond(padHourToLength: 2)
            : .minuteSecond(padMinuteToLength: 2)
        return Duration.seconds(totalSeconds).formatted(.time(pattern: pattern))
    }
}
