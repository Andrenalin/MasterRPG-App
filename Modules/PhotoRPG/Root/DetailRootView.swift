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
    
    var body: some View {
        content(listController: detailFolderListController)
            .navigate(to: $detailRoute)
            .onChange(of: detailFolderListController.listModel.subFolderRoute) {
                guard let subItemId = detailFolderListController.listModel.subFolderRoute else { return }
                detailRoute = PhotoDetailRoute.folder(subItemId)

                // Sync to AppNavigationModel
                if let navigationModel = detailFolderListController.listModel.navigationModel {
                    navigationModel.selectedEntryId = subItemId
                }
            }
            .onChange(of: detailRoute) {
                if detailRoute == nil {
                    // Back navigation detected
                    if detailFolderListController.listModel.subFolderRoute != nil {
                        detailFolderListController.listModel.subFolderRoute = nil
                    }

                    // Clear from AppNavigationModel
                    if let navigationModel = detailFolderListController.listModel.navigationModel {
                        navigationModel.selectedEntryId = nil
                    }
                }
            }
            .onChange(of: detailFolderListController.listModel.navigationModel?.selectedEntryId) {
                // Sync AppNavigationModel -> detailRoute
                guard let navigationModel = detailFolderListController.listModel.navigationModel else { return }

                if let entryId = navigationModel.selectedEntryId {
                    if detailRoute?.detail() != entryId {
                        detailRoute = PhotoDetailRoute.folder(entryId)
                        if detailFolderListController.listModel.subFolderRoute != entryId {
                            detailFolderListController.listModel.subFolderRoute = entryId
                        }
                    }
                } else {
                    if detailRoute != nil {
                        detailRoute = nil
                        if detailFolderListController.listModel.subFolderRoute != nil {
                            detailFolderListController.listModel.subFolderRoute = nil
                        }
                    }
                }
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
