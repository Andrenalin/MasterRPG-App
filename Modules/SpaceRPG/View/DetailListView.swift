// @copyright André Trettin

import CoreRPG
import SwiftUI

struct DetailListView: View {
    let root: SpaceRootModel
    let model: SpaceModel

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        DetailFolderListView(root: root, model: model)
            .tint(root.configurable.module.tint)
            .accentColor(root.configurable.module.tint)
            .userActivity(UserActivity.bundleIdentifierType, isActive: true) { activity in
                UserActivity.addPayLoad(for: activity, title: model.name, module: root.config.module, itemId: model.id)
            }
    }
}
