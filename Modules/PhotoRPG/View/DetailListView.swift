// @copyright André Trettin

import CoreRPG
import SwiftUI

struct DetailListView: View {
    let root: PhotoRootModel
    let model: PhotoModel

    var body: some View {
        let _ = Self._printChanges()
        DetailFolderListView(root: root, model: model)
            .toolbar {
                ToolbarItemGroup(placement: .secondaryActionAll) {
                    ControlGroup {
                        ConvertImageEditor(model: model)
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
