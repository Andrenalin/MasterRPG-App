// @copyright André Trettin

import SwiftUI

struct TableSheetView: View {
    let root: ItemRootController
    let model: SheetRootModel
    var addSearchable: Bool = true

    var body: some View {
        @Bindable var model = model

        listContentView
            .applyIf(addSearchable) {
                $0.searchable(text: $model.searchText, placement: .toolbarPrincipalAll, prompt: Text("Find in", bundle: .module))
            }
    }
}

private extension TableSheetView {
    var listContentView: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                SheetRootView(root: root, rootModel: model)
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

#Preview {
    TableSheetView(root: ItemRootController.fake, model: .fake)
}
