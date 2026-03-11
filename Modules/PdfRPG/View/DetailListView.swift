// @copyright André Trettin

import CoreRPG

import SwiftUI

struct DetailListView: View {
    init(root: PdfRootModel, model: PdfModel) {
        self.root = root
        self.model = model
        let listController = root.folderListController.copy(parentModel: model) as! FolderListController
        self._detailFolderListController = State(wrappedValue: listController)
    }
    
    let root: PdfRootModel
    let model: PdfModel

    @Environment(\.navigator) private var navigator
    
    @State private var detailFolderListController: FolderListController
    @State private var openFileWindowModel = OpenFileWindowModel(windowId: NetworkModules.pdf.viewerWindowId, route: { DetailRoute.viewer($0, nil) })

    var body: some View {
        content(listController: detailFolderListController)
            .onChange(of: detailFolderListController.listModel.subFolderRoute) {
                guard let subItemId = detailFolderListController.listModel.subFolderRoute else { return }
                navigator.navigate(to: PdfDetailRoute.folder(subItemId), method: .push)
                detailFolderListController.listModel.subFolderRoute = nil
            }
            .onAppear {
                root.editController.setCurrentItem(to: ItemRowTreeModel(itemId: model.id, typeId: root.config.module))
            }
    }
    
    func content(listController: any FolderListControllable) -> some View {
        ItemDetailRootView(detailListController: listController, selectedModel: model, editorAsBackground: false) {
        } editor: {
            fileAndPlayerView(model: model)
            
            SheetRootEditorView(root: root.rootController, linkControllable: root.linkControllable, model: model, module: root.config.module, headerTitle: String(localized: "Bookmarks", bundle: .module).localizedString, linkTypes: LinkPdfModuleTransferable.self)
        } entryEditor: {
            EntryEditorView(editController: root.editController, model: model, linkTypes: LinkPdfModuleTransferable.self)
        }
        .overlay {
            if openFileWindowModel.showItem {
                root.viewController.inlineViewer(root: root, with: openFileWindowModel.itemId, entryId: nil, withoutBookmark: false) {
                    openFileWindowModel.showItem = false
                }
            }
        }
        .environment(openFileWindowModel)
        .environment(root.folderListController.cacheListItemModel)
        .environment(root.listDisplayModel)
        .environment(root.searchModel)
        .environment(root.rootController)
        .tint(root.configurable.module.tint)
        .accentColor(root.configurable.module.tint)
    }
    
    func fileAndPlayerView(model: PdfModel) -> some View {
        HStack {
            HStack {
                FileImporterView(editControllable: root.editController, fileTypes: root.editController.fileUrlDataController?.fileTypes ?? [], itemId: model.id)
                
                Text(model.url?.path(percentEncoded: false) ?? "No file is set")
                    .frame(maxWidth: .infinity, alignment: .leading)
                
            }
            .opacity(model.specialCategory ? 0 : 1)
        }
        .padding()
    }

}

#Preview(traits: .mockData) {
    @Previewable @Environment(PdfRootModel.self) var root
    
    ManagedNavigationStack {
        DetailListView(root: root, model: root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items.first ?? PdfRootModel.previewSpaceId))
            .preferredColorScheme(.dark)
    }
}
