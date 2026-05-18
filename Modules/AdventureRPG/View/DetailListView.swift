// @copyright André Trettin

import CoreRPG
import SwiftUI

struct DetailListView: View {
    let root: AdventureRootModel
    let model: AdventureModel

    var body: some View {
        let _ = Self._printChanges()
        DetailFolderListView(root: root, model: model)
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
                    AdventureQuickEditorButton(model: model)
                    AdventureAddEntryButton(root: root, model: model)
#if !os(tvOS)
                    AdventureAIAssistantButton(root: root, model: model)
#endif
                }
            }
        }
#if os(iOS)
        ToolbarItemGroup(placement: .keyboard) {
            ForEach(root.editorLinkModel.firstRow, id: \.self) { module in
                AdventureAddLinkButton(root: root, model: model, module: module)
            }
        }
#endif
    }
}
