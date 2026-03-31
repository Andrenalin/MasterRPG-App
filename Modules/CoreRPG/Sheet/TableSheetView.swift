// @copyright André Trettin

import SwiftUI

struct TableSheetView: View {
    let root: ItemRootController
    let model: TableSheetModel

    var body: some View {
        @Bindable var model = model

        listContentView
            .searchable(text: $model.searchText, placement: .automatic, prompt: "Find in")
            .onChange(of: model.searchText) { oldValue, newValue in
                model.performSheetSearch(searchText: newValue)
            }
    }
}

private extension TableSheetView {
    var listContentView: some View {
        List {
            SheetView(root: root, model: model)
                .animation(.default, value: model.searchText)
        }
#if os(iOS)
        .background(root.configurable.module.tint.opacity(0.3).gradient)
        .scrollContentBackground(.hidden)
        .scrollEdgeEffectStyle(.soft, for: .all)
        .listRowSpacing(4)
#endif
        .toolbarTitleDisplayMode(.inline)
        .contentMargins(.horizontal, 8, for: .scrollContent)
    }
}
