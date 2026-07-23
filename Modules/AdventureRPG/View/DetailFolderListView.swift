// @copyright André Trettin

import CoreRPG
#if !os(tvOS)
import GeneratorRPG
#endif
import SwiftUI

#Preview(traits: .mockData) {
    @Previewable @Environment(AdventureRootModel.self) var root
    DetailFolderListView(root: root, model: root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items[0]), folderListController: root.folderListController)
}

struct DetailFolderListView: View {
    let root: AdventureRootModel
    let model: AdventureModel
    let folderListController: any FolderListControllable
    var isSubFolder: Bool = false

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()

        ItemDetailRootView(
            root: root.rootController,
            detailListController: folderListController,
            selectedModel: model,
            configuration: .init(isSubFolder: isSubFolder),
            linkTypes: LinkAdventureModuleTransferable.self
        ) {
            DetailEditorView(root: root, model: model)
        }
#if os(iOS)
        .sheetAIAssistantContext(
            module: root.configurable.module,
            itemId: model.id,
            rootModel: root.editController.editorModel.sheetRootModel
        )
#elseif !os(tvOS)
        .applyIf(root.editController.editorModel.sheetRootModel != nil) {
            $0.safeAreaInset(edge: .bottom, alignment: .center) {
                GlassEffectContainerAll {
                    aiAssistantView
                }
            }
        }
#endif
        .overlay {
            overlayContent
        }
    }

    // MARK: - Overlays

#if !os(tvOS) && !os(iOS)
    @ViewBuilder private var aiAssistantView: some View {
        if let sheetRootModel = root.editController.editorModel.sheetRootModel {
            SheetAIAssistantOverlayView(module: root.configurable.module, itemId: model.id, rootModel: sheetRootModel)
        }
    }
#endif

    @ViewBuilder private var overlayContent: some View {
        if root.openFileWindowModel.showItem {
            root.viewController.viewer(
                root: root,
                itemId: root.openFileWindowModel.itemId,
                configuration: ViewerConfiguration(closeButton: true, addToolbar: false)
            ) {
                root.openFileWindowModel.showItem = false
            }
        }
    }
}
