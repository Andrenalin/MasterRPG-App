// @copyright André Trettin

import AndrenalinKit
import CoreExternalRPG
import SwiftUI

struct DetailRootView: View {
    let editController: EditController
    let model: PdfModel

    @Environment(PdfRoot.self) private var root
    
    @State private var detailFolderListController: FolderListController?
    @State private var openFileWindowModel = OpenFileWindowModel(windowId: NetworkModules.pdf.viewerWindowId, route: { DetailRoute.viewer($0) })

    var body: some View {
        Group {
            if let detailFolderListController {
                content(listController: detailFolderListController)
                    .onChange(of: detailFolderListController.listModel.subFolderRoute) {
                        guard let subItemId = detailFolderListController.listModel.subFolderRoute else { return }
                        //navigator.navigate(to: AudioRoute.detail(subItemId), method: .push)
                        detailFolderListController.listModel.subFolderRoute = nil
                    }
            } else {
                Color.clear
                    .onAppear {
                        resetFolderListController()
                    }
            }
        }
    }
    
    func content(listController: any FolderListControllable) -> some View {
        ItemDetailRootView(detailListController: listController, selectedId: selectedModel?.id, editorAsBackground: true) {
        } editor: {
            if let model = selectedModel, let cacheController = root.cacheController {
                CachePhotoView(cacheController: cacheController, model: model, highResolution: false)
            }
        } inspector: {
            LinkRootView(type: .inspector)
        }
        .onChange(of: root.folderListController.listModel.selectedItemId, initial: true) {
            update()
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
        .tint(NetworkModules.pdf.tint)
        .accentColor(NetworkModules.pdf.tint)
    }
    
    func resetFolderListController() {
        guard let selectedModel else { return }
        guard let detailFolderListController, detailFolderListController.listModel.parentModel?.id == selectedModel.id else {
            self.detailFolderListController = root.folderListController.copy(parentModel: selectedModel) as? FolderListController
            return
        }
        return
    }
    
    var selectedModel: PdfModel? {
        root.folderListController.selectedModel(for: nil) as? PdfModel
    }

    func update() {
        resetFolderListController()
        if let item = root.folderListController.listModel.selectedModel as? PdfModel {
            if editController.editorModel.currentItemId != item.id {
                editController.setCurrentItem(to: ItemRowTreeModel(itemId: item.id, typeId: .space))
            }
        } else {
            if editController.editorModel.currentItemId != nil {
                editController.resetCurrentItem(with: "save".localizedString)
            }
        }
    }
}

struct PdfDetailObjectViewer: View {
    let editController: EditController
    let model: PdfModel
    
    @Environment(PdfRoot.self) private var root
    @Environment(GroupItemSelectionModel.self) private var selection
    
    var body: some View {
        PdfDetailViewer(item: ItemRowTreeModel(itemId: model.id, typeId: .pdf))
            .id(selectedModel.id)
    }
    
    private var selectedModel: PdfModel {
        guard let itemId = selection.selectedItem else { return model }
        return root.itemController.itemOrEmpty(for: itemId)
    }
}


#Preview(traits: .mockData) {
    @Previewable @Environment(PdfRoot.self) var root
    @Previewable @Environment(ListModel.self) var listModel
    
    if listModel.selectedItem == nil {
        Text("Hello")
            .onAppear {
                let id = root.itemController.itemDataModel.items.first ?? PdfRoot.previewSpaceId
                root.editController(type: .main).model = root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items.first ?? PdfRoot.previewSpaceId)
                listModel.selectedItem = ItemRowTreeModel(itemId: id, typeId: .space)
            }
    } else {
        ManagedNavigationStack {
            DetailRootView(editController: .preview, model: root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items.first ?? PdfRoot.previewSpaceId))
                .preferredColorScheme(.dark)
        }
    }
}
