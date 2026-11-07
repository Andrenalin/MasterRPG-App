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
    let onSeek: @MainActor (Double) -> Void

    // Tracks the drag independently of `currentTime` so intermediate drag
    // positions don't each trigger a seek — only the value at release does.
    // See CODE_AUDIT_Audio §7.1.
    @State private var isEditing = false
    @State private var editingValue: Double = 0

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
                    get: { isEditing ? editingValue : clampedCurrentTime },
                    set: { editingValue = $0 }
                ),
                in: sliderRange
            ) { editing in
                // A press that ends without moving must seek to where the thumb is, not to
                // the value of the last drag.
                if editing { editingValue = clampedCurrentTime }
                isEditing = editing
                if !editing {
                    onSeek(editingValue)
                }
            }
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
        PlayerTime.formatted(time: totalDuration)
    }

    private var accessibilityTimeValue: Text {
        Text(
            "\(Int(clampedCurrentTime.rounded())) seconds of \(Int(sliderRange.upperBound.rounded())) seconds",
            bundle: .module
        )
    }
}
