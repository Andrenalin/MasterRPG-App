// @copyright André Trettin

import CoreRPG
import SwiftUI

struct DetailFolderListView: View {
    let root: RuleRootModel
    let model: RuleModel
    let folderListController: any FolderListControllable
    var isSubFolder = false

    var body: some View {
        ItemDetailRootView(
            root: root.rootController,
            detailListController: folderListController,
            selectedModel: model,
            configuration: .init(isSubFolder: isSubFolder),
            linkTypes: LinkRuleModuleTransferable.self
        ) {
            DetailEditorView(root: root, model: model)
        }
        .openFileWindowOverlay(root.openFileWindowModel) { itemId, dismiss in
            root.viewController.viewer(
                root: root,
                itemId: itemId,
                configuration: ViewerConfiguration(closeButton: true),
                dismissAction: dismiss
            )
        }
    }
}

#Preview(traits: .mockData) {
    @Previewable @Environment(RuleRootModel.self) var root
    DetailFolderListView(
        root: root,
        model: .preview,
        folderListController: root.folderListController
    )
}
