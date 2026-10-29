// @copyright André Trettin

import CoreRPG
import SwiftUI

struct GameStatisticsAllSessionsView: View {
    @Bindable var model: GameStatisticsModel
    @State private var selection: Set<UUID> = []
    @State private var confirmsDelete = false
#if os(iOS) || os(visionOS)
    @State private var editMode: EditMode = .inactive
#endif

    var body: some View {
        List(selection: $selection) {
            ForEach(model.allSessions) { session in
                GameStatisticsSessionRow(session: session)
                    .tag(session.id)
            }
            .onDelete { offsets in
                let ids = Set(offsets.map { model.allSessions[$0].id })
                Task { await model.deleteSessions(ids: ids) }
            }
        }
        .themedListSurface()
        .navigationTitle(Text("All Games", bundle: .module))
        .overlay {
            if model.allSessions.isEmpty {
                ContentUnavailableView {
                    Label {
                        Text("No Games", bundle: .module)
                    } icon: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                }
            }
        }
        .toolbar {
#if os(iOS) || os(visionOS)
            ToolbarItem(placement: .primaryAction) {
                EditButton()
            }
#endif
#if !os(tvOS)
            ToolbarItem(placement: .primaryAction) {
                Button(role: .destructive) {
                    confirmsDelete = true
                } label: {
                    Label {
                        Text("Delete Selection", bundle: .module)
                    } icon: {
                        Image(systemName: "trash")
                    }
                }
                .disabled(selection.isEmpty)
            }
#endif
        }
#if os(iOS) || os(visionOS)
        .environment(\.editMode, $editMode)
#endif
        .confirmationDialog(
            Text("Delete \(selection.count) selected games’ statistics?", bundle: .module),
            isPresented: $confirmsDelete,
            titleVisibility: .visible
        ) {
            Button(role: .destructive) {
                let ids = selection
                Task { @MainActor in
                    await model.deleteSessions(ids: ids)
                    selection.subtract(ids)
                }
            } label: {
                Text("Delete Game Statistics", bundle: .module)
            }
        }
        .refreshable {
            await model.repair()
        }
        .task {
            await model.loadAllSessions()
        }
    }
}

#Preview {
    NavigationStack {
        GameStatisticsAllSessionsView(model: .previewFixture())
    }
}
