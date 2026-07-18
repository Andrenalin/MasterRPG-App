// @copyright André Trettin

#if os(macOS) || os(visionOS)
import Foundation
import SwiftUI

struct GameElapsedTimerText: View {
    let startDate: Date
    private let referenceDate: Date?

    init(startDate: Date, referenceDate: Date? = nil) {
        self.startDate = startDate
        self.referenceDate = referenceDate
    }

    var body: some View {
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
        .padding(.horizontal)
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
