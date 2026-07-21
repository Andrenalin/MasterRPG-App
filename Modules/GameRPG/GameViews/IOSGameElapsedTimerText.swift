// @copyright André Trettin

import CoreRPG
#if os(iOS)
import Foundation
import SwiftUI

struct IOSGameElapsedTimerText: View {
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
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .glassEffect(.regular, in: .capsule)
    }

    private func elapsedDuration(at date: Date) -> Duration {
        let elapsedSeconds = max(0, date.timeIntervalSince(startDate)).rounded(.down)
        return .seconds(elapsedSeconds)
    }
}

#Preview {
    IOSGameElapsedTimerText(
        startDate: GamePreviewData.referenceDate.addingTimeInterval(-5_400),
        referenceDate: GamePreviewData.referenceDate
    )
}
#endif
