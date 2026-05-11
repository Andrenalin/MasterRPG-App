// @copyright André Trettin

import CoreRPG
import SwiftUI

struct DetailRootView: View, Equatable {
    let root: MapRootModel
    let model: MapModel

    @Environment(AppWindowSizeModel.self) private var appSizeModel

    // Equatable conformance: only recreate if model.id changes
    static func == (lhs: DetailRootView, rhs: DetailRootView) -> Bool {
        lhs.model.id == rhs.model.id
    }

    var body: some View {
        DetailListView(root: root, model: model)
            .equatable()  // Only recreate if model.id changes
            .detailInspectorModifier()
            .applyIf(appSizeModel.mode == .regular) {
                $0.task(id: model.id) {
                    root.navigationModel.folderItems = []
                    root.navigationModel.folderModels = [:]
                }
            }
    }
}

#Preview(traits: .mockData) {
    @Previewable @Environment(MapRootModel.self) var root
    ManagedNavigationStack {
        DetailRootView(root: root, model: root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items.first ?? MapModel.previewId))
            .preferredColorScheme(.dark)
    }
}
