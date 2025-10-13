// @copyright André Trettin

import SwiftUI

public struct ImportDataModels: View {
    public init(importController: any ImportControllable, overwrite: Bool = false, isSaveGame: Bool = false, finishAction: @Sendable @escaping () async -> Void = {}) {
        self.importController = importController
        self.overwrite = overwrite
        self.isSaveGame = isSaveGame
        self.finishAction = finishAction
    }

    let importController: any ImportControllable
    let overwrite: Bool
    let isSaveGame: Bool
    let finishAction: @Sendable () async -> Void

    @State private var showImporter: Bool = false
    @State private var importTask: Task<Void, any Error>?
    @State private var importError: String?

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                showImporter.toggle()
            } label: {
                Label {
                    Text(buttonTitle, bundle: .module)
                } icon: { 
                    Image(systemName: "square.and.arrow.down")
                }
            }
#if !os(tvOS)
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [isSaveGame ? .gmsDocument : .rpgDocument]) { result in
                do {
                    let url: URL = try result.get()
                    importTask = importController.importUrl(from: url, withOverwrite: overwrite)
                } catch {
                    importError = error.localizedDescription
                }
            }
#endif
            .onChange(of: importController.importModel.isImportRunning, initial: true) {
                guard importController.importModel.isImportRunning else {
                    if importTask != nil {
                        importTask = nil
                    }
                    return
                }
                guard let importTask else { return }
                Task {
                    let result = await importTask.result
                    do {
                        importError = ""
                        _ = try result.get()
                        await finishAction()
                    } catch {
                        if let error = error as? ItemDataImportableError, error == ItemDataImportableError.cancel {
                            importError = "Import is cancelled, but \(importController.importModel.importedItems) are successfully imported."
                        } else {
                            importError = error.localizedDescription
                        }
                    }
                }
            }

            HStack {
                Text("Importing \(importController.importModel.importedItems) of \(importController.importModel.totalImportingItems)", bundle: .module)

                Spacer()

                Button {
                    importTask?.cancel()
                } label: {
                    Label("Cancel Import", systemImage: "xmark.square")
                }
                .disabled(importTask == nil)
            }
            if importController.importModel.totalImportingItems > 0 {
                ProgressView(value: Double(importController.importModel.importedItems), total: Double(importController.importModel.totalImportingItems))
                    .tint(Color.accentColor)
            }
            if let importError {
                Text(importError)
            }
        }
    }
    
    var buttonTitle: LocalizedStringKey {
        if overwrite {
            return "Import and Overwrite"
        }
        return isSaveGame ? "Load Game" : "Import"
    }
}
