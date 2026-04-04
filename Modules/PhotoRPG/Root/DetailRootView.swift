// @copyright André Trettin

import CoreRPG
import SwiftUI

struct DetailRootView: View {
    let root: PhotoRootModel
    let model: PhotoModel
    
    var body: some View {
        DetailListView(root: root, model: model)
            .detailInspectorModifier(folderListControllable: root.folderListController)
    }
}

struct DetailListView: View {
    init(root: PhotoRootModel, model: PhotoModel) {
        self.root = root
        self.model = model
        let listController = root.folderListController.copy(parentModel: model) as! FolderListController
        self._detailFolderListController = State(wrappedValue: listController)
    }
    
    let root: PhotoRootModel
    let model: PhotoModel
    
    @Environment(\.navigator) private var navigator
    
    @State private var detailFolderListController: FolderListController
    @State private var openFileWindowModel = OpenFileWindowModel(windowId: NetworkModules.photo.viewerWindowId, route: { DetailRoute.viewer($0) })
    
    @State private var detailRoute: PhotoDetailRoute?
    @State private var lastFolderId: UUID?
    @State private var canClean: Bool = false
    
    var body: some View {
        let _ = Self._printChanges()
        let _ = print("*** from \(model.id)")
        content(listController: detailFolderListController)
            .navigate(to: $detailRoute)
            .onChange(of: detailFolderListController.listModel.subFolderRoute) {
                //let _ = print("*** folderItems \(detailFolderListController.listModel.subFolderRoute) --> \(model.id)")
                guard lastFolderId == nil else { return }
                guard let subItemId = detailFolderListController.listModel.subFolderRoute else { return }
                lastFolderId = subItemId
                detailRoute = PhotoDetailRoute.folder(subItemId)
            }
            .onChange(of: detailRoute) { oldRoute, newRoute in
                guard let lastFolderId, oldRoute?.detail() == lastFolderId && newRoute == nil else { return }
//                if let index = root.navigationModel.folderItems.firstIndex(of: lastFolderId) {
//                    root.navigationModel.folderItems = Array(root.navigationModel.folderItems.prefix(index))
//                }
                detailFolderListController.listModel.resetListModel()
                self.lastFolderId = nil
            }
            .onAppear {
                print("OnAppear \(model.id)")
                if canClean {
                    //detailFolderListController.listModel.resetListModel()
                    canClean = false
                }
            }
            .onDisappear() {
                print("OnDissapear \(model.id)")
                canClean = true
            }
    }
    
    func content(listController: any FolderListControllable) -> some View {
        ItemDetailRootView(detailListController: listController, selectedModel: model, editorAsBackground: true) {
        } editor: {
            SelectedPhotoViewerView(model: model)
        }
        .overlay {
            if openFileWindowModel.showItem {
                root.viewController.viewer(root: root, itemId: openFileWindowModel.itemId, configuration: ViewerConfiguration(closeButton: true)) {
                    openFileWindowModel.showItem = false
                }
            }
        }
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
        ToolbarItemGroup(placement: .secondaryActionAll) {
            ControlGroup {
                ConvertImageEditor(model: model)
            }
        }
    }
}

#Preview(traits: .mockData) {
    @Previewable @Environment(PhotoRootModel.self) var root
    
    ManagedNavigationStack {
        DetailRootView(root: root, model: root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items.first ?? PhotoRootModel.previewPhotoId))
            .preferredColorScheme(.dark)
    }
}
