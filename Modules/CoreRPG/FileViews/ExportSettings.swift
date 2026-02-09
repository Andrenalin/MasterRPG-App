// @copyright André Trettin

import SwiftUI

public struct ExportDataModels: View {
    public init(exportController: any ExportControllable, export: @escaping () -> Task<Void, any Error>) {
        self.exportController = exportController
        self.export = export
    }

    let exportController: any ExportControllable
    let export: () -> Task<Void, any Error>

    @State private var showExporter: Bool = false
    @State private var exportTask: Task<Void, any Error>?
    @State private var exportError: String?

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                exportTask = export()
            } label: {
                Label {
                    Text("Export", bundle: .module)
                } icon: {
                    Image(systemName: "square.and.arrow.up")
                }
                
            }
            .disabled(exportController.exportModel.isExportRunning)
#if !os(tvOS)
            .fileMover(isPresented: $showExporter, file: URL.cachesDirectory.appending(path: "Export.gmz")) { _ in
            }
#endif
            .onChange(of: exportController.exportModel.isExportRunning, initial: true) {
                guard exportController.exportModel.isExportRunning else {
                    if exportTask != nil {
                        exportTask = nil
                    }
                    return
                }
                guard let exportTask else { return }
                Task { @MainActor in
                    let result = await exportTask.result
                    do {
                        exportError = ""
                        _ = try result.get()
                        showExporter.toggle()
                    } catch is CancellationError {
                        exportError = "Export is cancelled, but \(exportController.exportModel.exportedItems) are successfully exported."
                    } catch {
                        exportError = error.localizedDescription
                    }
                }
            }

            HStack {
                Text("Exporting \(exportController.exportModel.exportedItems) of \(exportController.exportModel.totalExportingItems)", bundle: .module)
                Spacer()
                Button {
                    exportTask?.cancel()
                } label: {
                    Label("Cancel Export", systemImage: "xmark.square")
                }
                .disabled(exportTask == nil)
            }
            if exportController.exportModel.totalExportingItems > 0 {
                ProgressView(value: Double(exportController.exportModel.exportedItems), total: Double(exportController.exportModel.totalExportingItems))
                    .tint(Color.accentColor)
            }
            if let exportError {
                Text(exportError)
            }
        }
    }
}
