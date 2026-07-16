// @copyright André Trettin

import SwiftUI

struct GameStatisticsSessionDetailView: View {
    let session: GameStatisticSessionSnapshot
    @Bindable var model: GameStatisticsModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirmsDelete = false

    var body: some View {
        List {
            Section {
                LabeledContent {
                    Text(session.startedAt, format: .dateTime.day().month(.wide).year().hour().minute())
                } label: {
                    Text("Started", bundle: .module)
                }
                LabeledContent {
                    Text(GameStatisticsFormat.duration(session.duration))
                } label: {
                    Text("Duration", bundle: .module)
                }
                LabeledContent {
                    Text(session.role.title)
                } label: {
                    Text("Role", bundle: .module)
                }
                if !session.characterName.isEmpty {
                    LabeledContent {
                        Text(session.characterName)
                    } label: {
                        Text("Character", bundle: .module)
                    }
                }
                if !session.adventureTitle.isEmpty {
                    LabeledContent {
                        Text(session.adventureTitle)
                    } label: {
                        Text("Adventure", bundle: .module)
                    }
                }
                if !session.masterName.isEmpty {
                    LabeledContent {
                        Text(session.masterName)
                    } label: {
                        Text("Game Master", bundle: .module)
                    }
                }
                LabeledContent {
                    Text(session.maxParticipantCount, format: .number)
                } label: {
                    Text("Largest Party", bundle: .module)
                }
            }

            Section {
                Button(role: .destructive) {
                    confirmsDelete = true
                } label: {
                    Label {
                        Text("Delete Game Statistics", bundle: .module)
                    } icon: {
                        Image(systemName: "trash")
                    }
                }
            }
        }
        .navigationTitle(Text("Game Summary", bundle: .module))
        .confirmationDialog(
            Text("Delete this game’s statistics?", bundle: .module),
            isPresented: $confirmsDelete,
            titleVisibility: .visible
        ) {
            Button(role: .destructive) {
                Task { @MainActor in
                    await model.deleteSession(id: session.id)
                    dismiss()
                }
            } label: {
                Text("Delete Game Statistics", bundle: .module)
            }
        }
    }
}

#Preview {
    let model = GameStatisticsModel.previewFixture()
    if let session = model.summary.recentSessions.first {
        NavigationStack {
            GameStatisticsSessionDetailView(session: session, model: model)
        }
    }
}
