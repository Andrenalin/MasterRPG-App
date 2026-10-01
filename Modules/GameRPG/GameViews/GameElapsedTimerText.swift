// @copyright André Trettin

import CoreRPG
#if os(iOS) || os(macOS) || os(visionOS)
import Foundation
import SwiftUI

/// The running game time. On iOS it floats over the map on a glass capsule. One view for every
/// platform (iOS had a copy). See CODE_AUDIT_19 §9.19.
struct GameElapsedTimerText: View {
    let startDate: Date
    private let referenceDate: Date?

    init(startDate: Date, referenceDate: Date? = nil) {
        self.startDate = startDate
        self.referenceDate = referenceDate
    }

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        Group {
            if let referenceDate {
                ElapsedTimeText(duration: elapsedDuration(at: referenceDate))
            } else {
                // The display only changes once a minute, so the timeline ticks once a minute,
                // anchored to the start so it changes exactly when the elapsed minutes do.
                // See CODE_AUDIT_20 §7.2.
                TimelineView(.periodic(from: startDate, by: 60)) { context in
                    ElapsedTimeText(duration: elapsedDuration(at: context.date))
                }
            }
        }
        .monospacedDigit()
#if os(iOS)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .glassEffect(.regular, in: .capsule)
#else
        .padding(.horizontal)
#endif
    }

    private func elapsedDuration(at date: Date) -> Duration {
        let elapsedSeconds = max(0, date.timeIntervalSince(startDate)).rounded(.down)
        return .seconds(elapsedSeconds)
    }
}

/// The elapsed game time, announced as "Game Time" with a spoken duration rather than a bare
/// "01:30". See CODE_AUDIT_20 §7.2.
private struct ElapsedTimeText: View {
    let duration: Duration

    var body: some View {
        Text(duration, format: .time(pattern: .hourMinute(padHourToLength: 2)))
            .accessibilityLabel(Text("Game Time", bundle: .module))
            .accessibilityValue(Text(duration, format: .units(allowed: [.hours, .minutes], width: .wide)))
    }
}

#Preview {
    GameElapsedTimerText(
        startDate: GamePreviewData.referenceDate.addingTimeInterval(-5_400),
        referenceDate: GamePreviewData.referenceDate
    )
}
#endif
