// @copyright André Trettin

import CoreRPG
#if !os(tvOS)
import GeneratorRPG
#endif
import SwiftUI

struct DetailFolderListView: View {
    let root: CharacterRootModel
    let model: ValueModel
    let folderListController: any FolderListControllable
    var isSubFolder: Bool = false

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        ItemDetailRootView(
            root: root.rootController,
            detailListController: folderListController,
            selectedModel: model,
            configuration: .init(isSubFolder: isSubFolder),
            linkTypes: LinkCharacterModuleTransferable.self
        ) {
            DetailEditorView(root: root, model: model)
        }
#if !os(tvOS)
        .applyIf(root.editController.editorModel.sheetRootModel != nil) {
            // A second live aiAssistantView here (e.g. as an invisible safeAreaInset
            // spacer) would double every stateful side effect (its .onChange fires
            // once per instance) — a fixed-height Color.clear reserves scroll space
            // without duplicating the view's state.
            $0.safeAreaInset(edge: .bottom, alignment: .center, spacing: 12) {
                Color.clear.frame(height: 64)
            }
            .overlay(alignment: .bottom) {
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
