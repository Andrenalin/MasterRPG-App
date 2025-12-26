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
    
    var body: some View {
        content(listController: detailFolderListController)
            .onChange(of: detailFolderListController.listModel.subFolderRoute) {
                guard let subItemId = detailFolderListController.listModel.subFolderRoute else { return }
                navigator.navigate(to: PhotoDetailRoute.folder(subItemId), method: .push)
                detailFolderListController.listModel.subFolderRoute = nil
            }
    }
    
    func content(listController: any FolderListControllable) -> some View {
        ItemDetailRootView(detailListController: listController, selectedModel: model, editorAsBackground: true) {
        } editor: {
            SelectedPhotoViewerView(model: model)
        }
        .overlay {
            if openFileWindowModel.showItem {
                root.viewController.inlineViewer(root: root, with: openFileWindowModel.itemId) {
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
}

struct SelectedPhotoViewerView: View {
    let model: PhotoModel
    
    @Environment(PhotoRootModel.self) var root
    @Environment(GroupItemSelectionModel.self) var selection
    
    var body: some View {
        ViewerRootView(model: selectedModel, externalViewer: false)
            .id(selection.selectedItem ?? model.id)
    }
    
    var selectedModel: PhotoModel {
        item ?? model
    }
    
    var item: PhotoModel? {
        guard let id = selection.selectedItem else { return nil }
        return root.itemController.itemSync(for: id)
    }
}


#Preview(traits: .mockData) {
    @Previewable @Environment(PhotoRootModel.self) var root
    
    ManagedNavigationStack {
        DetailRootView(root: root, model: root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items.first ?? PhotoRootModel.previewPhotoId))
            .preferredColorScheme(.dark)
    }
}
