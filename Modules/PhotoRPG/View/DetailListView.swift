// @copyright André Trettin

import CoreRPG
import SwiftUI

struct DetailListView: View {
    let root: PhotoRootModel
    let model: PhotoModel
    let folderListController: any FolderListControllable

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        DetailFolderListView(root: root, model: model, folderListController: folderListController)
            .toolbar {
                ToolbarItemGroup(placement: .secondaryActionAll) {
                    if model.url != nil && !model.specialCategory {
                        ControlGroup {
                            ConvertImageEditor(model: model)
                        }
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
