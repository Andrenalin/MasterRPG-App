// @copyright André Trettin

import CoreRPG
import SwiftUI

struct ViewerRootView: View {
    let model: TableModel
    let configuration: ViewerConfiguration
    var dismissAction: (() -> Void)? = nil

    @Environment(TableRootModel.self) private var root

    var body: some View {
        TableRootSheet(root: root.rootController, itemId: model.id, module: root.config.module, configuration: configuration, dismissAction: dismissAction)
            .id(model.id)
    }
}

#Preview("Goblin Loot", traits: .mockData) {
    ManagedNavigationStack {
        ViewerRootView(model: .preview, configuration: .init(), dismissAction: nil)
    }
}

#Preview("Roadside Encounters", traits: .mockData) {
    ManagedNavigationStack {
        ViewerRootView(model: .previewShortList, configuration: .init(), dismissAction: nil)
    }
}
