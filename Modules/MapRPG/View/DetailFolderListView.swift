// @copyright André Trettin

import CoreRPG
#if !os(tvOS)
import GeneratorRPG
#endif
import SwiftUI

#Preview(traits: .mockData) {
    @Previewable @Environment(MapRootModel.self) var root
    DetailFolderListView(root: root, model: root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items[0]), folderListController: root.folderListController)
}

struct DetailFolderListView: View {
    let root: MapRootModel
    let model: MapModel
    let folderListController: any FolderListControllable
    var isSubFolder: Bool = false

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()

        ItemDetailRootView(
            root: root.rootController,
            detailListController: folderListController,
            selectedModel: model,
            configuration: .init(isSubFolder: isSubFolder),
            linkTypes: LinkMapModuleTransferable.self
        ) {
            DetailEditorView(root: root, model: model)
        }
        .sheetAIAssistantPlacement(
            module: root.configurable.module,
            itemId: model.id,
            rootModel: root.editController.editorModel.sheetRootModel
        )
        .overlay {
            overlayContent
        }
    }

    // MARK: - Overlays

    @ViewBuilder private var overlayContent: some View {
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
