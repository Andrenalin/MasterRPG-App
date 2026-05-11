// @copyright André Trettin

import CoreRPG
import SwiftUI

struct DetailListView: View, Equatable {
    let root: PdfRootModel
    let model: PdfModel

    @Environment(\.navigator) private var navigator

    @State private var openFileWindowModel = OpenFileWindowModel(windowId: NetworkModules.pdf.viewerWindowId, route: { DetailRoute.viewer($0, nil) })

    static func == (lhs: DetailListView, rhs: DetailListView) -> Bool {
        lhs.model.id == rhs.model.id
    }

    var body: some View {
        DetailFolderListView(root: root, model: model)
            .equatable()
#if !os(tvOS)
            .toolbar {
                toolbarContent
            }
#endif
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

#if !os(tvOS)
    @ToolbarContentBuilder var toolbarContent: some ToolbarContent {
            ToolbarItem(placement: .secondaryAction) {
                if model.url != nil && !model.specialCategory {
                    Button {
                        navigator.navigate(to: PdfDetailRoute.pdfExtraction(model.id), method: .managedSheet)
                    } label: {
                        Label {
                            Text("Extract Information", bundle: .module)
                        } icon: {
                            Image(systemName: NetworkModules.generator.icon)
                        }
                    }
                    .disabled(openFileWindowModel.showItem)
                }
            }
    }
#endif

}

#Preview(traits: .mockData) {
    @Previewable @Environment(PdfRootModel.self) var root
    
    ManagedNavigationStack {
        DetailListView(root: root, model: root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items.first ?? PdfRootModel.previewSpaceId))
            .preferredColorScheme(.dark)
    }
}
