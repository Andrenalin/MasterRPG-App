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
                Text(
                    elapsedDuration(at: referenceDate),
                    format: .time(pattern: .hourMinute(padHourToLength: 2))
                )
            } else {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(
                        elapsedDuration(at: context.date),
                        format: .time(pattern: .hourMinute(padHourToLength: 2))
                    )
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

#Preview {
    GameElapsedTimerText(
        startDate: GamePreviewData.referenceDate.addingTimeInterval(-5_400),
        referenceDate: GamePreviewData.referenceDate
    )
}
#endif
