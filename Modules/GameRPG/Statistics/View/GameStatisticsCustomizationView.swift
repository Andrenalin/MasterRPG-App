// @copyright André Trettin

import SwiftUI

struct GameStatisticsCustomizationView: View {
    @Bindable var model: GameStatisticsModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirmsDeleteAll = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(
                        isOn: Binding(
                            get: { model.isCollectionEnabled },
                            set: { enabled in
                                Task { @MainActor in
                                    await model.setCollectionEnabled(enabled)
                                }
                            }
                        )
                    ) {
                        Label {
                            Text("Collect Game Statistics", bundle: .module)
                        } icon: {
                            Image(systemName: "chart.bar.doc.horizontal")
                        }
                    }
                } footer: {
                    Text("Only activity during a running game is collected. Message contents and media files are never stored.", bundle: .module)
                }

                Section {
                    ForEach(model.configuration.sectionOrder) { section in
                        GameStatisticsCustomizationRow(section: section, model: model)
                    }
                } header: {
                    Text("Dashboard", bundle: .module)
                } footer: {
                    Text("Choose which charts appear and arrange them in your preferred order.", bundle: .module)
                }

                Section {
#if !os(tvOS)
                    ShareLink(
                        item: GameStatisticsExportController().text(from: model.summary),
                        subject: Text("MasterRPG Game Statistics", bundle: .module),
                        message: Text("A summary of game activity collected during games.", bundle: .module)
                    ) {
                        Label {
                            Text("Export Statistics", bundle: .module)
                        } icon: {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
#endif
                    Button("Delete All Statistics", systemImage: "trash", role: .destructive) {
                        confirmsDeleteAll = true
                    }
                } footer: {
                    Text("This removes all locally stored and iCloud-synced game statistics from this database.", bundle: .module)
                }
            }
            .navigationTitle(Text("Customize Statistics", bundle: .module))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") {
                        dismiss()
                    }
                }
            }
            .confirmationDialog(
                Text("Delete all game statistics?", bundle: .module),
                isPresented: $confirmsDeleteAll,
                titleVisibility: .visible
            ) {
                Button("Delete All Statistics", role: .destructive) {
                    Task { @MainActor in
                        await model.deleteAll()
                    }
                }
            } message: {
                Text("This action cannot be undone.", bundle: .module)
            }
        }
    }

}

private struct GameStatisticsCustomizationRow: View {
    let section: GameStatisticsSection
    @Bindable var model: GameStatisticsModel

    var body: some View {
        HStack {
            Toggle(
                isOn: Binding(
                    get: { !model.configuration.hiddenSections.contains(section) },
                    set: { model.setSection(section, isVisible: $0) }
                )
            ) {
                Label(section.title, systemImage: section.systemImage)
            }

            Button("Move Up", systemImage: "chevron.up") {
                model.moveSection(section, offset: -1)
            }
            .labelStyle(.iconOnly)
            .disabled(model.configuration.sectionOrder.first == section)

            Button("Move Down", systemImage: "chevron.down") {
                model.moveSection(section, offset: 1)
            }
            .labelStyle(.iconOnly)
            .disabled(model.configuration.sectionOrder.last == section)
        }
    }
}

struct GameStatisticsSessionDetailView: View {
    let session: GameStatisticSessionSnapshot
    @Bindable var model: GameStatisticsModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirmsDelete = false

    var body: some View {
        List {
            Section {
                LabeledContent("Started") {
                    Text(session.startedAt, format: .dateTime.day().month(.wide).year().hour().minute())
                }
                LabeledContent("Duration", value: GameStatisticsFormat.duration(session.duration))
                LabeledContent("Role", value: session.role.title)
                if !session.characterName.isEmpty {
                    LabeledContent("Character", value: session.characterName)
                }
                if !session.adventureTitle.isEmpty {
                    LabeledContent("Adventure", value: session.adventureTitle)
                }
                if !session.masterName.isEmpty {
                    LabeledContent("Game Master", value: session.masterName)
                }
                LabeledContent("Largest Party", value: session.maxParticipantCount.formatted())
            }

            Section {
                Button("Delete Game Statistics", systemImage: "trash", role: .destructive) {
                    confirmsDelete = true
                }
            }
        }
        .navigationTitle(Text("Game Summary", bundle: .module))
        .confirmationDialog(
            Text("Delete this game’s statistics?", bundle: .module),
            isPresented: $confirmsDelete,
            titleVisibility: .visible
        ) {
            Button("Delete Game Statistics", role: .destructive) {
                Task { @MainActor in
                    await model.deleteSession(id: session.id)
                    dismiss()
                }
            }
        }
    }
}
