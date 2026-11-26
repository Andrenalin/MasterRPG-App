// @copyright André Trettin

import CoreRPG
#if !os(tvOS)
import GeneratorRPG
#endif
import SwiftUI

#Preview(traits: .mockData) {
    @Previewable @Environment(AdventureRootModel.self) var root
    DetailListView(
        root: root,
        model: root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items[0]),
        folderListController: root.folderListController
    )
}

struct DetailListView: View {
    let root: AdventureRootModel
    let model: AdventureModel
    let folderListController: any FolderListControllable

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
            .onChange(of: model.photoId) {
                withAnimation(reduceMotion ? nil : .default) { root.editController.editorModel.sheetRootModel?.updateFromRoot() }
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
/// identity/diffing instead of living as a computed property — mirrors the
/// same fix already applied to TableRPG's `DetailListView` (CODE_AUDIT_Table
/// §8.1). See CODE_AUDIT §8.3.
struct DetailListToolbarContent: ToolbarContent {
    let root: AdventureRootModel
    let model: AdventureModel

    @ToolbarContentBuilder var body: some ToolbarContent {
        ToolbarItemGroup(placement: .secondaryActionAll) {
            if !model.specialCategory && !root.openFileWindowModel.showItem {
                ControlGroup {
#if !os(tvOS)
                    AdventureExtractToolBarButton(model: model)
#endif
                }
            }
        }
#if os(iOS)
        // Disabled, not removed, while the AI composer is open: an emptied keyboard toolbar makes
        // UIKit swap the input accessory view during the focus-change keyboard animation, which
        // crashes on iPad (NSLayoutConstraint in -[UIInputWindowControllerHostingItem
        // inputAssistantHostView]).
        ToolbarItemGroup(placement: .keyboard) {
            ForEach(root.editorLinkModel.firstRow, id: \.self) { module in
                AdventureAddLinkButton(root: root, model: model, module: module)
                    .disabled(root.editController.editorModel.sheetRootModel?.isAIModeActive == true)
            }
        }
#endif
    }
}
