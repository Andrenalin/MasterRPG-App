// @copyright André Trettin

import CoreRPG
import SwiftUI

struct DetailListView: View, Equatable {
    let root: DiceRootModel
    let model: DiceModel

    @State private var openFileWindowModel = OpenFileWindowModel()

    static func == (lhs: DetailListView, rhs: DetailListView) -> Bool {
        lhs.model.id == rhs.model.id
    }

    var body: some View {
        DetailFolderListView(root: root, model: model)
            .equatable()
            .environment(openFileWindowModel)
            .environment(root.folderListController.cacheListItemModel)
            .environment(root.listDisplayModel)
            .environment(root.searchModel)
            .environment(root.rootController)
            .tint(root.configurable.module.tint)
            .accentColor(root.configurable.module.tint)
            .userActivity(UserActivity.bundleIdentifierType, isActive: true) { activity in
                UserActivity.addPayLoad(for: activity, title: model.name, module: root.config.module, itemId: model.id)
            }
    }
}
