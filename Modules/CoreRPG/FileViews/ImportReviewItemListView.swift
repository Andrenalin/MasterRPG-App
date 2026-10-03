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

            if !module.notInImportItems.isEmpty {
                Section {
                    ForEach(module.notInImportItems) { item in
                        ImportReviewItemRow(item: item)
                    }
                } header: {
                    Text("Not in Import", bundle: .module)
                } footer: {
                    Text("These items are in your library but not in the imported file. Choosing the imported version deletes them.", bundle: .module)
                }
            }
        }
        .themedListSurface()
    }
}

#Preview("Item List") {
    @Previewable @State var selectedID: ImportReviewItemModel.ID?
    ImportReviewItemListView(module: ImportReviewModel.preview.modules[0], selectedID: $selectedID)
}
