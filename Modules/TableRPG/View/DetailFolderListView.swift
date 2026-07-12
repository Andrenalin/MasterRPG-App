// @copyright André Trettin

import CoreRPG
import DiceRPG
#if !os(tvOS)
import GeneratorRPG
#endif
import SwiftUI

struct DetailFolderListView: View {
    let root: TableRootModel
    let model: TableModel
    let folderListController: any FolderListControllable
    var isSubFolder: Bool = false

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()

        ItemDetailRootView(
            root: root.rootController,
            detailListController: folderListController,
            selectedModel: model,
            configuration: .init(isSubFolder: isSubFolder),
            linkTypes: LinkTableModuleTransferable.self
        ) {
            DetailEditorView(root: root, model: model)
        }
#if !os(tvOS)
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

#if !os(tvOS)
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
                configuration: ViewerConfiguration(closeButton: true)
            ) {
                root.openFileWindowModel.showItem = false
            }
        }
    }
}
