// @copyright André Trettin

import CoreRPG
import SwiftUI

struct GameStatisticsCustomizationView: View {
    @Bindable var model: GameStatisticsModel
    @State private var confirmsDeleteAll = false
    @State private var pendingCollectionState: Bool?

    var body: some View {
        List {
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
                Text("Only activity during a running game is collected. Games shorter than 15 minutes are excluded. Message contents and media files are never stored.", bundle: .module)
            }

            Section {
                ForEach(model.configuration.sectionOrder) { section in
                    GameStatisticsCustomizationRow(section: section, model: model)
                }
#if !os(tvOS)
                .onMove(perform: model.moveSections)
#endif
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
                Button(role: .destructive) {
                    confirmsDeleteAll = true
                } label: {
                    Label {
                        Text("Delete All Statistics", bundle: .module)
                    } icon: {
                        Image(systemName: "trash")
                    }
                }
            } header: {
                Text("Data", bundle: .module)
            } footer: {
                Text("This removes all locally stored and iCloud-synced game statistics from this database.", bundle: .module)
            }
        }
        .themedListSurface()
#if os(iOS) || os(visionOS)
        .listStyle(.insetGrouped)
        .environment(\.editMode, .constant(.active))
#elseif os(macOS)
        .listStyle(.inset)
#endif
        .navigationTitle(Text("Customize Statistics", bundle: .module))
        .alert(
            Text("Delete all game statistics?", bundle: .module),
            isPresented: $confirmsDeleteAll
        ) {
            Button(role: .destructive) {
                Task { @MainActor in
                    await model.deleteAll()
                }
            } label: {
                Text("Delete All Statistics", bundle: .module)
            }
            Button(role: .cancel) {} label: {
                Text("Cancel", bundle: .module)
            }
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

#Preview {
    NavigationStack {
        GameStatisticsCustomizationView(model: .previewFixture())
    }
}
