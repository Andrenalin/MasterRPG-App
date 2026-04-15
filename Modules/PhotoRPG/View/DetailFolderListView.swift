// @copyright André Trettin

import CoreRPG
import SwiftUI

struct DetailFolderListView: View {
    let root: PhotoRootModel
    let model: PhotoModel
    
    @Environment(OpenFileWindowModel.self) private var openFileWindowModel
    @Environment(\.navigator) private var navigator
    @Environment(AppWindowSizeModel.self) private var appSizeModel
    
    @State private var detailRoute: PhotoDetailRoute?
    @State private var lastFolderId: UUID?
    @State private var showFolderDetail: Bool = false
    
    var detailFolderListController: FolderListController {
        let listModel = root.navigationModel.folderModels[model.id]
        
        let allListModel = listModel ?? root.folderListController.copyModel(parentModel: model)
        if listModel == nil {
            root.navigationModel.folderModels[model.id] = allListModel
        }
        
        return root.folderListController.copy(listModel: allListModel) as! FolderListController
    }
    
    var body: some View {
        content(listController: detailFolderListController)
            .applyIf(appSizeModel.mode == .compact) {
                $0.navigate(to: $detailRoute)
                    .onChange(of: detailFolderListController.listModel.subFolderRoute) {
                        guard let subItemId = detailFolderListController.listModel.subFolderRoute else { return }
                        detailRoute = PhotoDetailRoute.folder(subItemId)
                    }
                    .onChange(of: detailRoute) { oldRoute, newRoute in
                        guard detailRoute == nil else { return }
                        detailFolderListController.listModel.resetListModel()
                    }
            }
            .applyIf(appSizeModel.mode == .regular) {
                $0.onChange(of: root.navigationModel.folderItems) {
                    guard lastFolderId == nil, let subItemId = root.navigationModel.folderItems.last else { return }
                    lastFolderId = subItemId
                    withAnimation {
                        showFolderDetail = true
                    }
                }
                .overlay {
                    if showFolderDetail, let lastFolderId {
                        PhotoDetailRoute.folderInline(lastFolderId)
                            .padding(.top, 36)
                            .toolbar {
                                ToolbarItem(placement: .cancellationAction) {
                                    Button {
                                        showFolderDetail = false
                                        self.lastFolderId = nil
                                        detailFolderListController.listModel.resetListModel()
                                    } label: {
                                        Image(systemName: "xmark")
                                    }
                                }
                            }
                            .transition(.move(edge: .bottom))
                    }
                }
            }
    }
    
    func content(listController: any FolderListControllable) -> some View {
        ItemDetailRootView(
            detailListController: listController,
            selectedModel: model,
            configuration: .init(editorAsBackground: true, hasOverlay: false)
        ) {
            EmptyView()
        } editor: {
            SelectedPhotoViewerView(model: model)
        } overlay: {
            EmptyView()
        } entryEditor: {
            EmptyView()
        }
        .overlay {
            if openFileWindowModel.showItem {
                root.viewController.viewer(root: root, itemId: openFileWindowModel.itemId, configuration: ViewerConfiguration(closeButton: true)) {
                    openFileWindowModel.showItem = false
                }
            }
        }
    }
}
