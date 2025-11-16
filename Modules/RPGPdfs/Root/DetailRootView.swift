// @copyright André Trettin

import AndrenalinKit
import CoreExternalRPG
import SwiftUI

struct DetailRootView: View {
    init(root: PdfRootModel, editController: EditController, model: PdfModel, isSubFolder: Bool) {
        self.root = root
        self.editController = editController
        self.model = model
        self.isSubFolder = isSubFolder
        let listController = root.folderListController.copy(parentModel: model) as! FolderListController
        self._detailFolderListController = State(wrappedValue: listController)
    }
    
    let root: PdfRootModel
    let editController: EditController
    let model: PdfModel
    let isSubFolder: Bool

    @Environment(\.navigator) private var navigator
    
    @State private var detailFolderListController: FolderListController
    @State private var openFileWindowModel = OpenFileWindowModel(windowId: NetworkModules.pdf.viewerWindowId, route: { DetailRoute.viewer($0) })

    var body: some View {
        content(listController: detailFolderListController)
            .onChange(of: detailFolderListController.listModel.subFolderRoute) {
                guard let subItemId = detailFolderListController.listModel.subFolderRoute else { return }
                navigator.navigate(to: PdfDetailRoute.folder(subItemId), method: .push)
                detailFolderListController.listModel.subFolderRoute = nil
            }
    }
    
    func content(listController: any FolderListControllable) -> some View {
        ItemDetailRootView(detailListController: listController, selectedId: model.id, editorAsBackground: true) {
        } editor: {
            if let cacheController = root.cacheController {
                CachePhotoView(cacheController: cacheController, model: model, highResolution: false)
            }
        } inspector: {
        }
        .overlay {
            if openFileWindowModel.showItem {
                root.viewController.inlineViewer(root: root, with: openFileWindowModel.itemId, withoutBookmark: false) {
                    openFileWindowModel.showItem = false
                }
            }
        }
        .environment(openFileWindowModel)
        .environment(root.folderListController.cacheListItemModel)
        .environment(root.listDisplayModel)
        .environment(root.searchModel)
        .environment(root.rootController)
        .tint(root.module.tint)
        .accentColor(root.module.tint)
    }
}

struct PdfDetailObjectViewer: View {
    let editController: EditController
    let model: PdfModel
    
    @Environment(PdfRootModel.self) private var root
    @Environment(GroupItemSelectionModel.self) private var selection
    
    var body: some View {
        PdfDetailViewer(item: ItemRowTreeModel(itemId: model.id, typeId: root.module))
            .id(selectedModel.id)
    }
    
    private var selectedModel: PdfModel {
        guard let itemId = selection.selectedItem else { return model }
        return root.itemController.itemOrEmpty(for: itemId)
    }
}


#Preview(traits: .mockData) {
    @Previewable @Environment(PdfRootModel.self) var root
    @Previewable @Environment(ListModel.self) var listModel
    
    if listModel.selectedItem == nil {
        Text("Hello")
            .onAppear {
                let id = root.itemController.itemDataModel.items.first ?? PdfRootModel.previewSpaceId
                root.editController(type: .main).model = root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items.first ?? PdfRootModel.previewSpaceId)
                listModel.selectedItem = ItemRowTreeModel(itemId: id, typeId: root.module)
            }
    } else {
        ManagedNavigationStack {
            DetailRootView(root: root, editController: .preview, model: root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items.first ?? PdfRootModel.previewSpaceId), isSubFolder: false)
                .preferredColorScheme(.dark)
        }
    }
}
