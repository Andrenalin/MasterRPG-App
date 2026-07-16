// @copyright André Trettin

import SwiftUI

struct ImportStatusSection: View {
    let outcome: ImportOutcome
    let importModel: ItemDataImportModel
    @Binding var showImportFileChooser: Bool
    @Binding var loadUrl: URL?
    let urlProvider: (any ExampleUrlProvider)?
    let isSaveGame: Bool

    var body: some View {
        VStack {
            switch outcome {
            case .notStarted:
                ImportChooseUrlView(
                    showImportFileChooser: $showImportFileChooser,
                    loadUrl: $loadUrl,
                    urlProvider: urlProvider,
                    isSaveGame: isSaveGame,
                    importModel: importModel
                )
            case .running:
                Text("Importing \(importModel.importedItems) of \(importModel.totalImportingItems)", bundle: .module)
            case .finished:
                Text("Import is finished, \(importModel.importedItems) are successfully imported.", bundle: .module)
            case .cancelled:
                Text("Import is cancelled, but \(importModel.importedItems) are successfully imported.", bundle: .module)
            case .failed(let message):
                Text(message)
            }
        }
    }
}

#Preview {
    @Previewable @State var showImportFileChooser = false
    @Previewable @State var loadUrl: URL?
    ImportStatusSection(
        outcome: .notStarted,
        importModel: ItemDataImportModel(),
        showImportFileChooser: $showImportFileChooser,
        loadUrl: $loadUrl,
        urlProvider: FakeExampleUrlProvider(),
        isSaveGame: false
    )
    .padding()
}
