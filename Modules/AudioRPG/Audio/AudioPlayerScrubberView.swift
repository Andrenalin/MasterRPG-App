// @copyright André Trettin

import SwiftUI

struct AudioPlayerScrubberView: View {
    let currentTime: Double
    let totalDuration: Double
    let elapsedText: String
    let onSeek: @Sendable (Double) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(elapsedText)
                .font(.system(size: 10, weight: .medium))
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

            Text(formattedTotalTime)
                .font(.system(size: 10, weight: .medium))
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

    private var accessibilityTimeValue: String {
        "\(formatAccessibilityTime(currentTime)) seconds of \(formatAccessibilityTime(totalDuration)) seconds"
    }

    private func formatTime(_ time: Double) -> String {
        guard !time.isNaN && time.isFinite else { return "--:--" }

        let totalSeconds = Int(ceil(max(time, 0)))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }

    private func formatAccessibilityTime(_ time: Double) -> String {
        guard !time.isNaN && time.isFinite else { return "0" }
        return "\(Int(time.rounded()))"
    }
}
