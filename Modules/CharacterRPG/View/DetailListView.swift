// @copyright André Trettin

import CoreRPG
import SwiftUI

struct DetailListView: View {
    let root: CharacterRootModel
    let model: ValueModel
    let folderListController: any FolderListControllable

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()

        DetailFolderListView(root: root, model: model, folderListController: folderListController)
            .toolbar {
                toolbarContent
            }
            .tint(root.configurable.module.tint)
            .accentColor(root.configurable.module.tint)
            .userActivity(UserActivity.bundleIdentifierType, isActive: true) { activity in
                UserActivity.addPayLoad(for: activity, title: model.name, module: root.config.module, itemId: model.id)
            }
    }
    
    @ToolbarContentBuilder var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .secondaryActionAll) {
            if !model.specialCategory && !root.openFileWindowModel.showItem {
                ControlGroup {
                    AddEntryButton(root: root, model: model)
                    AddGroupButton(root: root, model: model)
                }
            }
        }
#if os(iOS)
        ToolbarItemGroup(placement: .keyboard) {
            ForEach(root.editorLinkModel.modulesRow, id: \.self) { module in
                AddLinkButton(root: root, model: model, module: module)
            }
        }
#endif
    }
}
