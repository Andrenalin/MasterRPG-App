// @copyright André Trettin

import SwiftUI

struct GameStatisticsSessionRow: View, Equatable {
    let session: GameStatisticSessionSnapshot

    var body: some View {
        HStack {
            Image(systemName: session.role.systemImage)
                .foregroundStyle(.secondary)
                .frame(minWidth: 24)
                .accessibilityLabel(Text(session.role.title))
            VStack(alignment: .leading) {
                Text(session.adventureTitle.isEmpty ? session.role.title : session.adventureTitle)
                    .bold()
                Text(session.startedAt, format: .dateTime.day().month(.abbreviated).year().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing) {
                Text(GameStatisticsFormat.duration(session.duration))
                Label {
                    Text(session.maxParticipantCount, format: .number)
                } icon: {
                    Image(systemName: "person.2")
                }
                .font(.caption)
                .accessibilityLabel(Text("\(session.maxParticipantCount) participants", bundle: .module))
            }
            .foregroundStyle(.secondary)
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
