// @copyright André Trettin

import CoreRPG
import SwiftUI

struct ViewerRootView: View {
    let model: MapModel
    let configuration: ViewerConfiguration
    var dismissAction: (() -> Void)? = nil

    @Environment(MapRootModel.self) private var root

    var body: some View {
        TableRootSheet(root: root.rootController, itemId: model.id, module: root.config.module, configuration: configuration, dismissAction: dismissAction)
            .id(model.id)
    }
}

#Preview(traits: .mockData) {
    @Previewable @Environment(MapRootModel.self) var root
    ManagedNavigationStack {
        ViewerRootView(model: root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items.first ?? MapModel.previewId), configuration: ViewerConfiguration())
            .preferredColorScheme(.dark)
    }
}
