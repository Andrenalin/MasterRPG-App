// @copyright André Trettin

import CoreRPG
import SwiftUI

struct DetailRootView: View {
    let root: RuleRootModel
    let model: RuleModel

    var body: some View {
        DetailListView(
            root: root,
            model: model,
            folderListController: root.folderListController
        )
        .detailInspectorModifier(root: root.rootController)
    }
}

#Preview(traits: .mockData) {
    @Previewable @Environment(RuleRootModel.self) var root
    ManagedNavigationStack {
        DetailRootView(root: root, model: .preview)
    }
}

