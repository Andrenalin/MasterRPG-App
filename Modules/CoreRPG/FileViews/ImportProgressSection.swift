// @copyright André Trettin

import SwiftUI

struct ImportProgressSection: View {
    let importModel: ItemDataImportModel
    var isFinalizing = false

    var body: some View {
        VStack {
            if (importModel.isImportRunning || isFinalizing)
                && importModel.totalImportingItems > 0 {
                ProgressView(
                    value: Double(importModel.importedItems),
                    total: Double(importModel.totalImportingItems)
                )
                .accessibilityLabel(Text("Import progress", bundle: .module))
            }

            if isFinalizing || importModel.isFinalizingImport {
                ImportFinalizationIndicator()
            }
        }
    }
}

private struct ImportFinalizationIndicator: View {
    var body: some View {
        ProgressView {
            Text("Finalizing import", bundle: .module)
        }
    }
}

#Preview {
    let model = {
        let model = ItemDataImportModel()
        model.isImportRunning = true
        model.importedItems = 8
        model.totalImportingItems = 8
        return model
    }()
    ImportProgressSection(importModel: model)
        .padding()
}
