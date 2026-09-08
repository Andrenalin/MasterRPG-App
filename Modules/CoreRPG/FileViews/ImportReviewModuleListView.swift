// @copyright André Trettin

import SwiftUI

struct ImportReviewModuleListView: View {
    @Bindable var model: ImportReviewModel

    var body: some View {
        List(model.modules, selection: $model.selectedModuleId) { module in
            ImportReviewModuleRow(module: module)
        }
        .themedListSurface()
        .navigationTitle(Text("Modules", bundle: .module))
        .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 280)
        .onChange(of: model.selectedModuleId) { _, newId in
            guard let newId else { return }
            model.select(moduleId: newId)
        }
    }
}

#Preview("Module List") {
    ImportReviewModuleListView(model: .preview)
}
