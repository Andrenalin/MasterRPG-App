// @copyright André Trettin

import SwiftUI

struct ImportReviewModuleListView: View {
    @Bindable var model: ImportReviewModel

    var body: some View {
        List(model.modules, selection: $model.selectedModuleID) { module in
            ImportReviewModuleRow(module: module)
        }
        .themedListSurface()
        .navigationTitle(Text("Modules", bundle: .module))
        .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 280)
        .onChange(of: model.selectedModuleID) { _, newID in
            guard let newID else { return }
            model.select(moduleID: newID)
        }
    }
}

#Preview("Module List") {
    ImportReviewModuleListView(model: .preview)
}
