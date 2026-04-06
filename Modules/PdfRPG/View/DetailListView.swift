// @copyright André Trettin

import CoreRPG
import SwiftUI

struct DetailListView: View {
    let root: PdfRootModel
    let model: PdfModel
    
    @Environment(\.navigator) private var navigator
    
    @State private var openFileWindowModel = OpenFileWindowModel(windowId: NetworkModules.pdf.viewerWindowId, route: { DetailRoute.viewer($0, nil) })
    
    var body: some View {
        DetailFolderListView(root: root, model: model)
            .toolbar {
                toolbarContent
            }
            .environment(openFileWindowModel)
            .environment(root.folderListController.cacheListItemModel)
            .environment(root.listDisplayModel)
            .environment(root.searchModel)
            .environment(root.rootController)
            .tint(root.configurable.module.tint)
            .accentColor(root.configurable.module.tint)
    }
    
    @ToolbarContentBuilder var toolbarContent: some ToolbarContent {
#if !os(tvOS)
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
#endif
    }
}

#Preview(traits: .mockData) {
    @Previewable @Environment(PdfRootModel.self) var root
    
    ManagedNavigationStack {
        DetailListView(root: root, model: root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items.first ?? PdfRootModel.previewSpaceId))
            .preferredColorScheme(.dark)
    }
}
