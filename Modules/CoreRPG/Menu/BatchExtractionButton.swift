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
                Text("Extract Information for \(item?.name ?? "")", bundle: .module)
            } icon: {
                Image(systemName: "sparkles")
            }
        }
        .accessibilityHint(Text("Analyzes selected items with AI", bundle: .module))
        .disabled(root.currentSelectedItemId == nil)
    }

    private var item: (any ItemDataAccessable)? {
        guard let selectedItemId = root.currentSelectedItemId else { return nil }
        return root.itemControllable.itemOrEmpty(for: selectedItemId)
    }
}

#Preview {
    BatchExtractionButton(root: ItemRootController.fake)
}
#endif
