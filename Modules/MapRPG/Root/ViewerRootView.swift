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

#Preview("Mega Dungeon", traits: .mockData) {
    ManagedNavigationStack {
        ViewerRootView(model: .preview, configuration: .init())
            .preferredColorScheme(.dark)
    }
}

#Preview("Shadowfen Crossing", traits: .mockData) {
    ManagedNavigationStack {
        ViewerRootView(model: .previewForest, configuration: .init())
            .preferredColorScheme(.dark)
    }
}
