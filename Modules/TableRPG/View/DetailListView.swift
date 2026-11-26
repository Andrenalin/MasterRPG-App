// @copyright André Trettin

import CoreRPG
#if !os(tvOS)
import GeneratorRPG
#endif
import SwiftUI

#Preview(traits: .mockData) {
    @Previewable @Environment(TableRootModel.self) var root
    DetailListView(
        root: root,
        model: root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items.first ?? TableModel.previewId),
        folderListController: root.folderListController
    )
}

struct DetailListView: View {
    let root: TableRootModel
    let model: TableModel
    let folderListController: any FolderListControllable

    @Environment(\.navigator) private var navigator    

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        DetailFolderListView(root: root, model: model, folderListController: folderListController)
            .toolbar {
                DetailListToolbarContent(root: root, model: model)
            }
            .themedSurface()
            .moduleTint(root.configurable.module)
            .userActivity(UserActivity.bundleIdentifierType, isActive: true) { activity in
                UserActivity.addPayLoad(for: activity, title: model.name, module: root.config.module, itemId: model.id)
#if !os(tvOS)
                root.addSiriContext(to: activity, itemId: model.id)
#endif
            }
#if !os(tvOS)
            .task(id: model.id) {
                await root.donateSiriViewingIntent(for: model.id)
            }
            .onChange(of: model.diceId) {
                withAnimation { root.editController.editorModel.sheetRootModel?.updateFromRoot() }
            }
            .sheetAIAssistant(
                generatorRoot: root.generatorRoot,
                rootModel: root.editController.editorModel.sheetRootModel,
                module: root.configurable.module
            )
#endif
    }

}

/// Extracted from `DetailListView` so the toolbar content gets its own
/// identity/diffing instead of living as a computed property. See
/// CODE_AUDIT_Table §8.1.
struct DetailListToolbarContent: ToolbarContent {
    let root: TableRootModel
    let model: TableModel

    @ToolbarContentBuilder var body: some ToolbarContent {
        ToolbarItemGroup(placement: .secondaryActionAll) {
            if !model.specialCategory && !root.openFileWindowModel.showItem {
#if !os(tvOS)
                TableExtractToolBarButton(model: model)
#endif
            }
        }
#if os(iOS)
        // Disabled, not removed, while the AI composer is open: an emptied keyboard toolbar makes
        // UIKit swap the input accessory view during the focus-change keyboard animation, which
        // crashes on iPad (NSLayoutConstraint in -[UIInputWindowControllerHostingItem
        // inputAssistantHostView]).
        ToolbarItemGroup(placement: .keyboard) {
            ForEach(root.editorLinkModel.modulesRow, id: \.self) { module in
                AddLinkButton(root: root, model: model, module: module)
                    .disabled(root.editController.editorModel.sheetRootModel?.isAIModeActive == true)
            }
        }
#endif
    }
}
