// @copyright André Trettin

import SwiftUI

public struct ExportProgressPanelView: View {
    /// Lets this panel's own presentation animation settle before the export work begins,
    /// rather than starting mid-transition. See CODE_AUDIT §9.14.
    private static let exportStartPresentationDelay: Duration = .seconds(0.5)
    public init(exportController: any ExportControllable, showOptions: Bool = false, isSaveGame: Bool = false, saveGameName: String? = nil, exporter: @escaping () -> ItemModuleIds, finishedAction: @escaping () -> Void = {}) {
        self.exportController = exportController
        self.showOptions = showOptions
        self.isSaveGame = isSaveGame
        self.saveGameName = saveGameName
        self.exporter = exporter
        self.finishAction = finishedAction
        self._outcome = State(wrappedValue: showOptions ? .notStarted : .running)
    }

    let exportController: any ExportControllable
    let showOptions: Bool
    let isSaveGame: Bool
    let saveGameName: String?
    let exporter: () -> (ItemModuleIds)
    let finishAction: () -> Void

    @Environment(\.navigator) private var navigator

    @State private var exportModel = ItemDataExportModel()
    @State private var showExporter = false
    @State private var exportTask: Task<Void, any Error>?
    @State private var saveUrl: URL?
    @State private var outcome: ExportOutcome = .running

    public var body: some View {
        NavigationStack {
            VStack {
                ExportProgressPanelProgressView(exportModel: exportModel)

                ExportProgressPanelStatusView(outcome: $outcome, exportModel: exportModel, startExport: startExport)
            }
            .padding()
            .navigationTitle(Text("Exporting", bundle: .module))
            .navigationBarTitleDisplayModeAll(.inline)
            .task {
                guard outcome != .notStarted else { return }
                await startExport()
            }
            .onDisappear {
                // A system-gesture dismissal must not leave a detached export writing with no
                // UI owner (a no-op once the export has finished). See CODE_AUDIT_16 §3.5.
                exportTask?.cancel()
            }
#if !os(tvOS)
            .fileMover(isPresented: $showExporter, file: saveUrl) { result in
                switch result {
                case .success:
                    outcome = .finished
                case .failure(let error):
                    outcome = error is CancellationError ? .cancelled : .failed(error.localizedDescription)
                }
            }
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) {
                        exportTask?.cancel()
                        navigator.dismiss()
                        finishAction()
                    } label: {
                        Label { Text("Cancel", bundle: .module) } icon: { Image(systemName: "xmark") }
                    }
                    .disabled(outcome != .notStarted && outcome != .running)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm) {
                        navigator.dismiss()
                        finishAction()
                    } label: {
                        Label { Text("Ok", bundle: .module) } icon: { Image(systemName: "checkmark") }
                    }
                    .disabled(outcome == .notStarted || outcome == .running)
                }
            }
        }
    }

    // `private` would hide this from the sibling extracted subview structs below (private
    // nested-type access only extends to this declaration and same-file extensions of it,
    // not to unrelated top-level types) — `fileprivate` keeps it scoped to this file only.
    fileprivate enum ExportOutcome: Equatable {
        case notStarted
        case running
        case finished
        case cancelled
        case failed(String)
    }
}

#Preview {
    ExportProgressPanelView(
        exportController: FakeExportController.fake,
        showOptions: true,
        exporter: { .init() }
    )
}

private extension ExportProgressPanelView {
    func startExport() async {
        do {
            try await Task.sleep(for: Self.exportStartPresentationDelay)
            if isSaveGame {
                let url = exportController.exportUrl(isSaveGame: true, adventureTitle: saveGameName)
                let task = exportController.createExport(itemIds: exporter(), into: url, exportModel: exportModel)
                exportTask = task
                saveUrl = url
            } else {
                let (task, url) = exportController.export(ids: exporter(), exportModel: exportModel)
                exportTask = task
                saveUrl = url
            }
            _ = try await exportTask?.value
            showExporter.toggle()
        } catch is CancellationError {
            outcome = .cancelled
        } catch {
            outcome = .failed(error.localizedDescription)
        }
    }
}

// MARK: - Extracted subviews (CODE_AUDIT §8.3)

private struct ExportProgressPanelProgressView: View {
    let exportModel: ItemDataExportModel

    @ViewBuilder var body: some View {
        if exportModel.isExportRunning && exportModel.totalExportingItems > 0 {
            ProgressView(
                value: Double(exportModel.exportedItems),
                total: Double(exportModel.totalExportingItems)
            )
            .tint(Color.accentColor)
            .accessibilityLabel(Text("Export progress", bundle: .module))
        }
    }
}

private struct ExportProgressPanelStatusView: View {
    @Binding var outcome: ExportProgressPanelView.ExportOutcome
    let exportModel: ItemDataExportModel
    let startExport: () async -> Void

    var body: some View {
        VStack {
            switch outcome {
            case .notStarted:
                ExportProgressPanelOptionView(outcome: $outcome, exportModel: exportModel, startExport: startExport)
            case .running:
                Text("Exporting \(exportModel.exportedItems) of \(exportModel.totalExportingItems)", bundle: .module)
            case .finished:
                Text("Export is finished, \(exportModel.totalExportingItems) are successfully exported.", bundle: .module)
            case .cancelled:
                Text("Export is cancelled, nothing written", bundle: .module)
            case .failed(let message):
                Text(message)
            }
        }
    }
}

private struct ExportProgressPanelOptionView: View {
    @Binding var outcome: ExportProgressPanelView.ExportOutcome
    @Bindable var exportModel: ItemDataExportModel
    let startExport: () async -> Void

    var body: some View {
        VStack(spacing: 20) {
            Button {
                outcome = .running
                Task {
                    await startExport()
                }
            } label: {
                Text("Start export", bundle: .module)
            }

            Toggle(isOn: $exportModel.exportWithoutFileData) {
                Label {
                    Text("Export only data not the files", bundle: .module)
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                }
            }

            Text("This option let you export only the database data without the files included in the export. If you store your file in iCloud but don't want to use CloudKit for sync the database. Use this option with care you might losing the file data and you cannot exchange it with other users.", bundle: .module)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
