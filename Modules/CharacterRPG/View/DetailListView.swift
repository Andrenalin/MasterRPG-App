// @copyright André Trettin

import CoreRPG
import SwiftUI

#Preview(traits: .mockData) {
    @Previewable @Environment(CharacterRootModel.self) var root
    DetailListView(
        root: root,
        model: root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items[0]),
        folderListController: root.folderListController
    )
}

struct DetailListView: View {
    let root: CharacterRootModel
    let model: ValueModel
    let folderListController: any FolderListControllable

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()

        DetailFolderListView(root: root, model: model, folderListController: folderListController)
#if os(iOS)
            .toolbar {
                toolbarContent
            }
#endif
            .tint(root.configurable.module.tint)
            .accentColor(root.configurable.module.tint)
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
#endif
    }

#if os(iOS)
    @ToolbarContentBuilder var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .keyboard) {
            if root.editController.editorModel.sheetRootModel?.isAIModeActive != true {
                ForEach(root.editorLinkModel.modulesRow, id: \.self) { module in
                    AddLinkButton(root: root, model: model, module: module)
                }
            }
        }
    }
#endif
}
