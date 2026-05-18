// @copyright André Trettin

import CoreRPG
import SwiftUI

struct DetailFolderListView: View {
    let root: PhotoRootModel
    let model: PhotoModel
    
    @Environment(AppWindowSizeModel.self) private var appSizeModel
    
    @State private var detailRoute: PhotoDetailRoute?
    @State private var showFolderOverlay: Bool = false

    var body: some View {
        let _ = Self._printChanges()
        
        ItemDetailRootView(
            root: root.rootController,
            detailListController: detailListController,
            selectedModel: model,
            configuration: .init(editorAsBackground: true),
            linkTypes: EmptyLinkTransferable.self
        ) {
            ViewerRootView(model: model, configuration: ViewerConfiguration(addToolbar: false))
        }
        .overlay {
            overlayContent
        }
        .applyIf(appSizeModel.mode == .compact) {
            $0.navigate(to: $detailRoute)
                .onChange(of: currentListModel.subFolderRoute) { _, newRoute in
                    if let subItemId = newRoute {
                        detailRoute = PhotoDetailRoute.folder(subItemId)
                    }
                }
                .onChange(of: detailRoute) { _, newRoute in
                    if newRoute == nil {
                        currentListModel.resetListModel()
                    }
                }
        }
        .onChange(of: root.navigationModel.folderItems) {
            handleFolderItemsChange()
        }
    }
    
    // MARK: - Computed Properties
    
    /// Creates or retrieves the list controller for this model
    /// ItemDetailRootView will copy it internally, so we don't need @State
    private var detailListController: FolderListControllable {
        root.folderListController.copy(listModel: currentListModel)
    }
    
    /// Gets or creates the cached list model for this detail view
    private var currentListModel: FolderListModel {
        if let existing = root.navigationModel.folderModels[model.id] {
            return existing
        }
        
        // Create and cache new model
        let newModel = root.folderListController.copyModel(parentModel: model)
        root.navigationModel.folderModels[model.id] = newModel
        return newModel
    }
    
    // MARK: - Overlays
    
    @ViewBuilder
    private var overlayContent: some View {
        // File viewer overlay (all modes)
        if root.openFileWindowModel.showItem {
            root.viewController.viewer(
                root: root,
                itemId: root.openFileWindowModel.itemId,
                configuration: ViewerConfiguration(closeButton: true)
            ) {
                root.openFileWindowModel.showItem = false
            }
        }
        
        // Folder detail overlay (regular mode only)
        if appSizeModel.mode == .regular, 
           showFolderOverlay,
           let folderId = root.navigationModel.folderItems.last {
            PhotoDetailRoute.folderInline(folderId)
                .padding(.top, 36)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            closeFolderOverlay()
                        } label: {
                            Image(systemName: "xmark")
                        }
                    }
                }
                .transition(.move(edge: .bottom))
        }
    }
    
    // MARK: - Actions
    
    private func handleFolderItemsChange() {
        guard appSizeModel.mode == .regular else { return }
        guard !showFolderOverlay, root.navigationModel.folderItems.last != nil else { return }
        
        withAnimation {
            showFolderOverlay = true
        }
    }
    
    private func closeFolderOverlay() {
        showFolderOverlay = false
        currentListModel.resetListModel()
    }
}
