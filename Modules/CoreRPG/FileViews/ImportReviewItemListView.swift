// @copyright André Trettin

import SwiftUI

struct ImportReviewItemListView: View {
    let module: ImportReviewModule
    @Binding var selectedID: ImportReviewItemModel.ID?

    var body: some View {
        List(selection: $selectedID) {
            if !module.addedItems.isEmpty {
                Section {
                    ForEach(module.addedItems) { item in
                        ImportReviewItemRow(item: item)
                    }
                } header: {
                    Text("Added", bundle: .module)
                }
            }

            if !module.changedItems.isEmpty {
                Section {
                    ForEach(module.changedItems) { item in
                        ImportReviewItemRow(item: item)
                    }
                } header: {
                    Text("Changed", bundle: .module)
                }
            }
        }
    }
}

#Preview("Item List") {
    @Previewable @State var selectedID: ImportReviewItemModel.ID?
    ImportReviewItemListView(module: ImportReviewModel.preview.modules[0], selectedID: $selectedID)
}
