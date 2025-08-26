// @copyright André Trettin

import SwiftUI

public struct ExportProgressFile: View {
    public init(exportController: any ExportControllable, exporter: @escaping () -> (Task<Void, any Error>, URL), finishedAction: @escaping () -> Void = {}) {
        self.exportController = exportController
        self.exporter = exporter
        self.finishAction = finishedAction
    }

    let exportController: any ExportControllable
    let exporter: () -> (Task<Void, any Error>, URL)
    let finishAction: () -> Void

    @Environment(\.dismiss) private var dismiss
    
    @State private var showExporter: Bool = false
    @State private var exportTask: Task<Void, any Error>?
    @State private var saveUrl: URL?

    @State private var hasError: Bool = false
    @State private var isCancelled: Bool = false
    @State private var exportError: String?

    public var body: some View {
        NavigationStack {
            @Bindable var exportModel = exportController.exportModel
            VStack {
                Button {
                    exportTask?.cancel()
                    dismiss()
                } label: {
                    Label { Text("Cancel", bundle: .module) } icon: { Image(systemName: "xmark.square") }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .disabled(!exportController.exportModel.isExportRunning)
                
                if exportController.exportModel.isExportRunning &&  exportController.exportModel.totalExportingItems > 0 {
                    ProgressView(value: Double(exportController.exportModel.exportedItems), total: Double(exportController.exportModel.totalExportingItems))
                        .tint(Color.accentColor)
                }
                
                VStack {
                    if hasError {
                        if isCancelled {
                            Text("Export is cancelled, but \(exportController.exportModel.exportedItems) are successfully exported.", bundle: .module)
                        } else {
                            Text(exportError ?? "")
                        }
                    } else {
                        Text("Exporting \(exportController.exportModel.exportedItems) of \(exportController.exportModel.totalExportingItems)", bundle: .module)
                    }
                }
                .frame(width: 320)
            }
            .padding()
            .task {
                try? await Task.sleep(for: .seconds(0.5))
                let (exportTask, saveUrl) = exporter()
                self.exportTask = exportTask
                self.saveUrl = saveUrl
                let result = await exportTask.result
                do {
                    _ = try result.get()
                    showExporter.toggle()
                } catch is CancellationError {
                    isCancelled = true
                    hasError = true
                } catch {
                    exportError = error.localizedDescription
                    hasError = true
                }
            }
#if !os(tvOS)
            .fileMover(isPresented: $showExporter, file: saveUrl ?? URL(string: "Export.gmz")) { _ in
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
                    .disabled(exportController.exportModel.isExportRunning)
                }
            }
        }
    }

    var exportTitle: String {
        exportController.exportModel.isExportRunning ?
        "Exporting \(exportController.exportModel.exportedItems) of \(exportController.exportModel.totalExportingItems)" : "Export Finished \(exportError ?? "")"
    }
}
