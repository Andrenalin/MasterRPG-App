// @copyright André Trettin

import SwiftUI

struct TableFirstSheetView: View {
    let root: ItemRootController
    let model: TableFirstSheetModel

    var body: some View {
        @Bindable var model = model

        listContentView
            .searchable(text: $model.searchText, placement: .toolbarPrincipalAll, prompt: Text("Find in", bundle: .module))
            .onChange(of: model.searchText) { oldValue, newValue in
                model.performSheetSearch(searchControllable: model.searchControllable, searchText: newValue)
            }
    }
}

private extension TableFirstSheetView {
    var listContentView: some View {
        List {
            SheetFirstView(root: root, model: model)
                .animation(.default, value: model.searchText)
        }
#if os(iOS)
        .background(model.moduleTint.opacity(0.3).gradient)
        .scrollContentBackground(.hidden)
        .scrollEdgeEffectStyle(.soft, for: .all)
        .listRowSpacing(4)
#endif
        .toolbarTitleDisplayMode(.inline)
        .contentMargins(.horizontal, 8, for: .scrollContent)
    }
}
