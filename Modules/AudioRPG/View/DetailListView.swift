// @copyright André Trettin

import CoreRPG
import SwiftUI

struct DetailListView: View {
    let root: AudioRootModel
    let model: AudioModel
    let folderListController: FolderListController

    var body: some View {
        DetailFolderListView(root: root, model: model, folderListController: folderListController)
            .toolbar {
                ToolbarItem(placement: .secondaryActionAll) {
                    if model.url != nil || model.specialCategory {
                        PlayToolbarButton(root: root, model: model)
                    }
                }
            }
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
}
