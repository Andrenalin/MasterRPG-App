// @copyright André Trettin

import CoreRPG
import SwiftUI

struct DetailFolderListView: View {
    let root: AudioRootModel
    let model: AudioModel
    
    @Environment(\.navigator) private var navigator
    @Environment(\.appSizeMode) private var appSizeMode
    
    @State private var detailRoute: AudioDetailRoute?
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
            .applyIf(appSizeMode == .compact) {
                $0.navigate(to: $detailRoute)
                    .onChange(of: detailFolderListController.listModel.subFolderRoute) {
                        guard let subItemId = detailFolderListController.listModel.subFolderRoute else { return }
                        detailRoute = AudioDetailRoute.folder(subItemId)
                    }
                    .onChange(of: detailRoute) { oldRoute, newRoute in
                        guard detailRoute == nil else { return }
                        detailFolderListController.listModel.resetListModel()
                    }
            }
            .applyIf(appSizeMode == .regular) {
                $0.onChange(of: root.navigationModel.folderItems) {
                    guard lastFolderId == nil, let subItemId = root.navigationModel.folderItems.last else { return }
                    lastFolderId = subItemId
                    withAnimation {
                        showFolderDetail = true
                    }
                }
                .overlay {
                    if showFolderDetail, let lastFolderId {
                        AudioDetailRoute.folderInline(lastFolderId)
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
        ItemDetailRootView(detailListController: listController, selectedModel: model, editorAsBackground: false) {
        } editor: {
            fileAndPlayerView(model: model)
        } overlay: {
            playerView
        }
    }
    
    func fileAndPlayerView(model: AudioModel) -> some View {
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
    
    var playerView: some View {
        AudioPlayerBarView()
            .padding()
    }
}
