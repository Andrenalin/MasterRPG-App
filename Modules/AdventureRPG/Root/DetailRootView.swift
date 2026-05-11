// @copyright André Trettin

import CoreRPG
import SwiftUI

struct DetailRootView: View, Equatable {
    let root: AdventureRootModel
    let model: AdventureModel

    @Environment(AppWindowSizeModel.self) private var appSizeModel

    // Equatable conformance: only recreate if model.id changes
    static func == (lhs: DetailRootView, rhs: DetailRootView) -> Bool {
        lhs.model.id == rhs.model.id
    }

    var body: some View {
        let _ = Self._printChanges()
        DetailListView(root: root, model: model)
            .equatable()  // Only recreate if model.id changes
            .detailInspectorModifier()
            .applyIf(appSizeModel.mode == .regular) {
                $0.task(id: model.id) {
                    root.navigationModel.folderItems <=> []
                    if !root.navigationModel.folderModels.isEmpty {
                        root.navigationModel.folderModels = [:]
                    }
                }
            }
    }
}

#Preview(traits: .mockData) {
    @Previewable @Environment(AdventureRootModel.self) var root

    ManagedNavigationStack {
        DetailRootView(root: root, model: root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items.first ?? AdventureModel.previewId))
            .preferredColorScheme(.dark)
    }
}
