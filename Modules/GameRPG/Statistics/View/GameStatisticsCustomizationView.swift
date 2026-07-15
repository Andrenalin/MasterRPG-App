// @copyright André Trettin

import SwiftUI

struct GameStatisticsCustomizationView: View {
    @Bindable var model: GameStatisticsModel
    @State private var confirmsDeleteAll = false
    @State private var pendingCollectionState: Bool?

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    HStack {
                        if pendingCollectionState != nil {
                            ProgressView()
                                .controlSize(.small)
                        }

                        Toggle(isOn: collectionEnabledBinding) {
                            Text("Collect Game Statistics", bundle: .module)
                        }
                        .labelsHidden()
                        .disabled(pendingCollectionState != nil)
                    }
                } label: {
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
            } header: {
                Text("Data", bundle: .module)
            } footer: {
                Text("This removes all locally stored and iCloud-synced game statistics from this database.", bundle: .module)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(Text("Customize Statistics", bundle: .module))
        .alert(
            Text("Delete all game statistics?", bundle: .module),
            isPresented: $confirmsDeleteAll
        ) {
            Button("Delete All Statistics", role: .destructive) {
                Task { @MainActor in
                    await model.deleteAll()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.", bundle: .module)
        }
    }

    private var collectionEnabledBinding: Binding<Bool> {
        Binding(
            get: { pendingCollectionState ?? model.isCollectionEnabled },
            set: { enabled in
                guard pendingCollectionState == nil,
                      enabled != model.isCollectionEnabled
                else { return }

                pendingCollectionState = enabled
                Task { @MainActor in
                    await model.setCollectionEnabled(enabled)
                    pendingCollectionState = nil
                }
            }
        )
    }
}

private struct GameStatisticsCustomizationRow: View {
    let section: GameStatisticsSection
    @Bindable var model: GameStatisticsModel

    var body: some View {
        LabeledContent {
            HStack {
                Toggle(section.title, isOn: sectionVisibilityBinding)
                    .labelsHidden()
#if os(macOS)
                    .controlSize(.mini)
#endif

                Menu {
                    Button("Move Up", systemImage: "arrow.up") {
                        model.moveSection(section, offset: -1)
                    }
                    .disabled(model.configuration.sectionOrder.first == section)

                    Button("Move Down", systemImage: "arrow.down") {
                        model.moveSection(section, offset: 1)
                    }
                    .disabled(model.configuration.sectionOrder.last == section)
                } label: {
                    Label {
                        Text("Reorder", bundle: .module)
                    } icon: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                }
#if os(iOS)
                .labelStyle(.iconOnly)
#endif
            }
        } label: {
            Label(section.title, systemImage: section.systemImage)
        }
    }

    private var sectionVisibilityBinding: Binding<Bool> {
        Binding(
            get: { !model.configuration.hiddenSections.contains(section) },
            set: { model.setSection(section, isVisible: $0) }
        )
    }
}

#if os(iOS) || os(macOS)
struct GameStatisticsCustomizationInspectorView: View {
    @Bindable var model: GameStatisticsModel
#if os(iOS)
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
#endif

    var body: some View {
#if os(iOS)
        NavigationStack {
            GameStatisticsCustomizationView(model: model)
                .toolbar {
                    if horizontalSizeClass == .compact {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done", systemImage: "checkmark") {
                                dismiss()
                            }
                        }
                    }
                }
        }
        .presentationSizing(.form)
        .inspectorColumnWidth(min: 340, ideal: 400, max: 480)
#else
        GameStatisticsCustomizationView(model: model)
            .inspectorColumnWidth(min: 340, ideal: 400, max: 480)
#endif
    }
}
#endif

struct GameStatisticsCustomizationSheetView: View {
    @Bindable var model: GameStatisticsModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            GameStatisticsCustomizationView(model: model)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done", systemImage: "checkmark") {
                            dismiss()
                        }
                    }
                }
        }
        .presentationSizing(.form)
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
