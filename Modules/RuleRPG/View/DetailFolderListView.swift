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
        .overlay {
            if root.openFileWindowModel.showItem {
                root.viewController.viewer(
                    root: root,
                    itemId: root.openFileWindowModel.itemId,
                    configuration: ViewerConfiguration(closeButton: true)
                ) {
                    root.openFileWindowModel.showItem = false
                }
            }
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
