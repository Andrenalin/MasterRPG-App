// @copyright André Trettin

import SwiftUI

struct TableSheetView: View {
    let root: ItemRootController
    let model: SheetRootModel

    var body: some View {
        @Bindable var model = model

        listContentView
            .searchable(text: $model.searchText, placement: .toolbarPrincipalAll, prompt: Text("Find in", bundle: .module))
//            .onChange(of: model.searchText) { oldValue, newValue in
//                model.performSheetSearch(searchControllable: model.searchControllable, searchText: newValue)
//            }
    }
}

private extension TableSheetView {
    var listContentView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                SheetView(root: root, model: model)
                    .animation(.default, value: model.searchText)
            }
        }
#if os(iOS)
        .background(root.configurable.module.tint.opacity(0.3).gradient)
        .scrollContentBackground(.hidden)
        .scrollEdgeEffectStyle(.soft, for: .all)
#endif
        .toolbarTitleDisplayMode(.inline)
        .contentMargins(.horizontal, 8, for: .scrollContent)
    }
}
