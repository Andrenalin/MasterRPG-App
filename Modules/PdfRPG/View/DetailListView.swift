// @copyright André Trettin

import CoreRPG
import SwiftUI

struct DetailListView: View {
    let root: PdfRootModel
    let model: PdfModel
    let folderListController: any FolderListControllable

    @Environment(\.navigator) private var navigator

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        DetailFolderListView(root: root, model: model, folderListController: folderListController)
#if !os(tvOS)
            .toolbar {
                toolbarContent
            }
#endif
            .tint(root.configurable.module.tint)
            .accentColor(root.configurable.module.tint)
            .userActivity(UserActivity.bundleIdentifierType, isActive: true) { activity in
                UserActivity.addPayLoad(for: activity, title: model.name, module: root.config.module, itemId: model.id)
            }
    }

#if !os(tvOS)
    @ToolbarContentBuilder var toolbarContent: some ToolbarContent {
            ToolbarItem(placement: .secondaryAction) {
                if model.url != nil && !model.specialCategory {
                    ExtractToolBarButton(root: root, model: model)
                }
            }
    }
#endif

}

#Preview(traits: .mockData) {
    @Previewable @Environment(PdfRootModel.self) var root
    ManagedNavigationStack {
        DetailListView(root: root, model: root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items.first ?? PdfRootModel.previewSpaceId), folderListController: root.folderListController)
            .preferredColorScheme(.dark)
    }
}
