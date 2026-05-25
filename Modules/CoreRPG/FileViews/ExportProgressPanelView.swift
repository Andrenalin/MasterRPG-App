// @copyright André Trettin

import SwiftUI

public struct ExportProgressPanelView: View {
    public init(exportController: any ExportControllable, isSaveGame: Bool = false, exporter: @escaping () -> ItemModuleIds, finishedAction: @escaping () -> Void = {}) {
        self.exportController = exportController
        self.isSaveGame = isSaveGame
        self.exporter = exporter
        self.finishAction = finishedAction
    }

    let exportController: any ExportControllable
    let isSaveGame: Bool
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
                    case .finished:
                        Text("Export is finished, \(exportModel.totalExportingItems) are successfully exported.", bundle: .module)
                    case .cancelled:
                        Text("Export is cancelled, nothing written", bundle: .module)
                    case .failed(let message):
                        Text(message)
                    }
                }
                .frame(width: 320)
            }
            .padding()
            .navigationTitle(Text("Exporting", bundle: .module))
            .navigationBarTitleDisplayModeAll(.inline)
            .task {
                do {
                    try await Task.sleep(for: .seconds(0.5))
                    if isSaveGame {
                        let url = exportController.exportUrl(isSaveGame: true)
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
#if !os(tvOS)
            .fileMover(isPresented: $showExporter, file: saveUrl) { _ in
                outcome = .finished
            }
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        exportTask?.cancel()
                        navigator.dismiss()
                    } label: {
                        Label { Text("Cancel", bundle: .module) } icon: { Image(systemName: "xmark") }
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        navigator.dismiss()
                        finishAction()
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
        case finished
        case cancelled
        case failed(String)
    }
}
