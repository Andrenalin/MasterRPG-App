// @copyright André Trettin

import CoreRPG
import SwiftUI

struct DetailListView: View {
    let root: MapRootModel
    let model: MapModel
    let folderListController: any FolderListControllable

    var body: some View {
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
            if !model.specialCategory {
                ControlGroup {
                    QuickEditorButton(model: model)
                    MapEditorButton(model: model)
                    EditTileButton(model: model)
                    AddEntryButton(root: root, model: model)
#if !os(tvOS)
                    MapExtractToolBarButton(model: model)
#endif
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
