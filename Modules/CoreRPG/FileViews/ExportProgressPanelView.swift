// @copyright André Trettin

import SwiftUI

/// How an export panel was closed. See CODE_AUDIT_26 §5.21.
public enum ExportPanelResult: Sendable, Equatable {
    /// The export was written (and moved to its destination).
    case finished
    /// The user cancelled, dismissed the panel or cancelled the file mover.
    case cancelled
    /// The export failed.
    case failed

    /// Whether "Save and Quit" goes on to quit the game: only after the game was saved.
    public var endsSaveAndQuit: Bool { self == .finished }
}

public struct ExportProgressPanelView: View {
    /// Lets this panel's own presentation animation settle before the export work begins,
    /// rather than starting mid-transition. See CODE_AUDIT §9.14.
    private static let exportStartPresentationDelay: Duration = .seconds(0.5)
    public init(exportController: any ExportControllable, showOptions: Bool = false, isSaveGame: Bool = false, saveGameName: String? = nil, exporter: @escaping () -> ItemModuleIds, finishedAction: @escaping () -> Void = {}, onResult: @escaping (ExportPanelResult) -> Void = { _ in }) {
        self.exportController = exportController
        self.showOptions = showOptions
        self.isSaveGame = isSaveGame
        self.saveGameName = saveGameName
        self.exporter = exporter
        self.finishAction = finishedAction
        self.onResult = onResult
        self._outcome = State(wrappedValue: showOptions ? .notStarted : .running)
    }

    let exportController: any ExportControllable
    let showOptions: Bool
    let isSaveGame: Bool
    let saveGameName: String?
    let exporter: () -> (ItemModuleIds)
    let finishAction: () -> Void
    /// Called once when the panel closes, with how it ended.
    let onResult: (ExportPanelResult) -> Void

    @Environment(\.navigator) private var navigator

    @State private var exportModel = ItemDataExportModel()
    @State private var showExporter = false
    @State private var exportTask: Task<Void, any Error>?
    @State private var saveUrl: URL?
    @State private var outcome: ExportOutcome = .running
    @State private var hasReported = false

    public var body: some View {
        NavigationStack {
            VStack {
                ExportProgressPanelProgressView(exportModel: exportModel)

                ExportProgressPanelStatusView(outcome: $outcome, exportModel: exportModel, startExport: startExport)
            }
            .padding()
            .navigationTitle(Text("Exporting", bundle: .module))
            .navigationBarTitleDisplayModeAll(.inline)
            // Owned by the view: runs at appear when no options are shown and again when the
            // option screen starts the export, and is cancelled with the panel. The id is only
            // "options shown", so later outcome changes do not restart or cancel it.
            // See CODE_AUDIT_26 §5.66.
            .task(id: outcome == .notStarted) {
                guard outcome == .running else { return }
                await startExport()
            }
            .onDisappear {
                // A system-gesture dismissal must not leave a detached export writing with no
                // UI owner (a no-op once the export has finished). See CODE_AUDIT_16 §3.5.
                exportTask?.cancel()
                // A swipe-down dismissal never presses a button: it still has to say how it ended.
                report(outcome.panelResult ?? .cancelled)
            }
#if !os(tvOS)
            .fileMover(isPresented: $showExporter, file: saveUrl) { result in
                switch result {
                case .success:
                    outcome = .finished
                case .failure(let error):
                    // Closing the destination picker is a cancel, not a failure; the temporary
                    // export file is removed then.
                    let userCancelled = error is CancellationError || (error as? CocoaError)?.code == .userCancelled
                    if userCancelled {
                        if let saveUrl { try? FileManager.default.removeItem(at: saveUrl) }
                        outcome = .cancelled
                    } else {
                        outcome = .failed(error.localizedDescription)
                    }
                }
            }
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) {
                        exportTask?.cancel()
                        report(.cancelled)
                        navigator.dismiss()
                        finishAction()
                    } label: {
                        Label { Text("Cancel", bundle: .module) } icon: { Image(systemName: "xmark") }
                    }
                    .disabled(outcome != .notStarted && outcome != .running)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm) {
                        report(outcome.panelResult ?? .cancelled)
                        navigator.dismiss()
                        finishAction()
                    } label: {
                        Label { Text("OK", bundle: .module) } icon: { Image(systemName: "checkmark") }
                    }
                    .disabled(outcome == .notStarted || outcome == .running)
                }
            }
        }
    }

    // `private` would hide this from the sibling extracted subview structs below (private
    // nested-type access only extends to this declaration and same-file extensions of it,
    // not to unrelated top-level types) — `fileprivate` keeps it scoped to this file only.
    enum ExportOutcome: Equatable {
        case notStarted
        case running
        case finished
        case cancelled
        case failed(String)

        /// How the panel ended when it closes in this state; `nil` while nothing has ended it.
        var panelResult: ExportPanelResult? {
            switch self {
            case .finished: .finished
            case .cancelled: .cancelled
            case .failed: .failed
            case .notStarted, .running: nil
            }
        }
    }

    private func report(_ result: ExportPanelResult) {
        guard !hasReported else { return }
        hasReported = true
        onResult(result)
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
