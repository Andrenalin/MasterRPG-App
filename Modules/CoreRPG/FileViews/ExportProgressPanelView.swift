// @copyright André Trettin

import SwiftUI

public struct ExportProgressPanelView: View {
    public init(exportController: any ExportControllable, exporter: @escaping () -> (Task<Void, any Error>, URL), finishedAction: @escaping () -> Void = {}) {
        self.exportController = exportController
        self.exporter = exporter
        self.finishAction = finishedAction
    }

    let exportController: any ExportControllable
    let exporter: () -> (Task<Void, any Error>, URL)
    let finishAction: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var showExporter = false
    @State private var exportTask: Task<Void, any Error>?
    @State private var saveUrl: URL?
    @State private var outcome: ExportOutcome = .running

    public var body: some View {
        NavigationStack {
            let exportModel = exportController.exportModel
            VStack {
                if exportModel.isExportRunning && exportModel.totalExportingItems > 0 {
                    ProgressView(
                        value: Double(exportModel.exportedItems),
                        total: Double(exportModel.totalExportingItems)
                    )
                    .tint(Color.accentColor)
                    .accessibilityLabel(Text("Export progress", bundle: .module))
                }

                VStack {
                    switch outcome {
                    case .running:
                        Text("Exporting \(exportModel.exportedItems) of \(exportModel.totalExportingItems)", bundle: .module)
                    case .cancelled:
                        Text("Export is cancelled, but \(exportModel.exportedItems) are successfully exported.", bundle: .module)
                    case .failed(let message):
                        Text(message)
                    }
                }
                .frame(width: 320)
            }
            .padding()
            .navigationTitle(Text("Exporting", bundle: .module))
            .navigationBarTitleDisplayMode(.inline)
            .task {
                do {
                    try await Task.sleep(for: .seconds(0.5))
                    let (task, url) = exporter()
                    exportTask = task
                    saveUrl = url
                    _ = try await task.value
                    showExporter.toggle()
                } catch is CancellationError {
                    outcome = .cancelled
                } catch {
                    outcome = .failed(error.localizedDescription)
                }
            }
#if !os(tvOS)
            .fileMover(isPresented: $showExporter, file: saveUrl) { _ in
                finishAction()
            }
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        exportTask?.cancel()
                        dismiss()
                    } label: {
                        Label { Text("Cancel", bundle: .module) } icon: { Image(systemName: "xmark") }
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Label { Text("Ok", bundle: .module) } icon: { Image(systemName: "checkmark") }
                    }
                    .disabled(exportModel.isExportRunning)
                }
            }
        }
    }

    private enum ExportOutcome {
        case running
        case cancelled
        case failed(String)
    }
}
