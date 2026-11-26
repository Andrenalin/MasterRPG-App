// @copyright André Trettin

import SwiftUI

#if !os(tvOS)
struct BatchExtractionButton: View {
    let root: any ItemRootControllable

    var body: some View {
        Button {
            root.navigationModel.triggerBatchExtraction = true
        } label: {
            Label {
                Text.itemMenuTitle(name: item?.name, plain: "Extract", named: "Extract Information for \(item?.name ?? "")")
            } icon: {
                Image(systemName: "sparkles")
            }
        }
        .accessibilityHint(Text("Analyzes selected items with AI", bundle: .module))
        .disabled(root.currentSelectedItemId == nil)
    }

    private var item: (any ItemDataAccessible)? {
        guard let selectedItemId = root.currentSelectedItemId else { return nil }
        return root.itemControllable.itemOrEmpty(for: selectedItemId)
    }
}

#Preview {
    BatchExtractionButton(root: ItemRootController.fake)
}
#endif
