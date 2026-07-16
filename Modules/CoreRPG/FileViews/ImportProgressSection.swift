// @copyright André Trettin

import SwiftUI

struct ImportProgressSection: View {
    let importModel: ItemDataImportModel

    var body: some View {
        if importModel.isImportRunning && importModel.totalImportingItems > 0 {
            ProgressView(
                value: Double(importModel.importedItems),
                total: Double(importModel.totalImportingItems)
            )
            .tint(Color.accentColor)
            .accessibilityLabel(Text("Import progress", bundle: .module))
        }
    }
}

#Preview {
    let model = {
        let model = ItemDataImportModel()
        model.isImportRunning = true
        model.importedItems = 3
        model.totalImportingItems = 8
        return model
    }()
    ImportProgressSection(importModel: model)
        .padding()
}
