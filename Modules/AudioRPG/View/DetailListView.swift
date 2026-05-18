// @copyright André Trettin

import CoreRPG
import SwiftUI

struct DetailListView: View {
    let root: AudioRootModel
    let model: AudioModel

    var body: some View {
        DetailFolderListView(root: root, model: model)
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
            }
    }
}
