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

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        DetailFolderListView(root: root, model: model, folderListController: folderListController)
            .toolbar {
                toolbarContent
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
                withAnimation { root.editController.editorModel.sheetRootModel?.updateFromRoot() }
            }
            .sheetAIAssistant(
                generatorRoot: root.generatorRoot,
                rootModel: root.editController.editorModel.sheetRootModel,
                module: root.configurable.module
            )
#endif
    }

    @ToolbarContentBuilder var toolbarContent: some ToolbarContent {
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
        ToolbarItemGroup(placement: .keyboard) {
            if root.editController.editorModel.sheetRootModel?.isAIModeActive != true {
                ForEach(root.editorLinkModel.firstRow, id: \.self) { module in
                    AdventureAddLinkButton(root: root, model: model, module: module)
                }
            }
        }
#endif
    }
}
