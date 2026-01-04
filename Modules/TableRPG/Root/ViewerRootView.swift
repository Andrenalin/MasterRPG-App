// @copyright André Trettin

import CoreRPG
import SwiftUI

struct ViewerRootView: View {
    let model: TableModel
    var windowMode: Bool = false
    var dismissAction: (() -> Void)? = nil

    @Environment(TableRootModel.self) private var root


    var body: some View {
        TableRootSheet(root: root.rootController, itemId: model.id, module: root.config.module, windowMode: windowMode, dismissAction: dismissAction)
    }
}

#Preview(traits: .mockData) {
    @Previewable @Environment(TableRootModel.self) var root
    ManagedNavigationStack {
        ViewerRootView(model: root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items.first ?? TableModel.previewId), dismissAction: nil)
    }
}
