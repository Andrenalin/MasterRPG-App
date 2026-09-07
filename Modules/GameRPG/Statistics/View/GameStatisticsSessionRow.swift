// @copyright André Trettin

import SwiftUI

struct GameStatisticsSessionRow: View, Equatable {
    let session: GameStatisticSessionSnapshot
    let showsDisclosureIndicator: Bool

    init(session: GameStatisticSessionSnapshot, showsDisclosureIndicator: Bool = true) {
        self.session = session
        self.showsDisclosureIndicator = showsDisclosureIndicator
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(session.adventureTitle.isEmpty ? session.role.title : session.adventureTitle)
                    .bold()
                Text(session.startedAt, format: .dateTime.day().month(.abbreviated).year().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(GameStatisticsFormat.duration(session.duration))
                .foregroundStyle(.secondary)
            if showsDisclosureIndicator {
                Image(systemName: "chevron.forward")
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    let sessions = GameStatisticsPreviewController().summary(
        referenceDate: GamePreviewData.referenceDate,
        calendar: GamePreviewData.calendar
    ).recentSessions
    if let session = sessions.first {
        GameStatisticsSessionRow(session: session)
            .padding()
    }
}
