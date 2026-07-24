// @copyright André Trettin

import CoreRPG
import SwiftUI

struct DetailListView: View {
    let root: RuleRootModel
    let model: RuleModel
    let folderListController: any FolderListControllable

    @Environment(\.navigator) private var navigator

    var body: some View {
        DetailFolderListView(
            root: root,
            model: model,
            folderListController: folderListController
        )
        .toolbar {
            if !model.specialCategory {
                ToolbarItem(placement: .secondaryActionAll) {
                    Button("Edit All Sections", systemImage: "list.bullet.rectangle") {
                        navigator.navigate(to: RuleEditorRoute.quickEditor(model.id))
                    }
                }
            }
        }
        .tint(NetworkModules.rule.tint)
        .userActivity(UserActivity.bundleIdentifierType, isActive: true) { activity in
            UserActivity.addPayLoad(
                for: activity,
                title: model.name,
                module: .rule,
                itemId: model.id
            )
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

#Preview(traits: .mockData) {
    @Previewable @Environment(RuleRootModel.self) var root
    DetailListView(
        root: root,
        model: .preview,
        folderListController: root.folderListController
    )
}
